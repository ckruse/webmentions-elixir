defmodule Webmentions do
  def send_webmentions(source_url, root_selector \\ ".h-entry") do
    case HTTPoison.get(source_url, [], follow_redirects: true) do
      {:ok, response} ->
        if success?(:ok, response) do
          send_webmentions_for_doc(response.body, source_url, root_selector)
        else
          {:error, response.status_code}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Atom.to_string(reason)}
    end
  end

  def send_webmentions_for_doc(html, source_url, root_selector \\ ".h-entry") do
    document = Floki.parse(html)
    content = Floki.find(document, root_selector)

    links =
      Floki.find(content, "a[href]")
      |> Enum.filter(fn x ->
        s =
          Floki.attribute(x, "rel")
          |> List.first()
          |> to_string

        not String.contains?(s, "nofollow")
      end)

    sent =
      Enum.reduce(links, [], fn link, acc ->
        dst = Floki.attribute(link, "href") |> List.first() |> abs_uri(source_url, document)

        case discover_endpoint(dst) do
          {:ok, nil} ->
            acc ++ [{:ok, dst, nil, "no endpoint found"}]

          {:ok, ""} ->
            acc ++ [{:ok, dst, nil, "no endpoint found"}]

          {:error, result} ->
            acc ++ [{:err, dst, nil, result}]

          {:ok, endpoint} ->
            case send_webmention(endpoint, source_url, dst) do
              :ok ->
                acc ++ [{:ok, dst, endpoint, "sent"}]

              {:error, v} ->
                acc ++ [{:err, dst, endpoint, "sending failed: #{v}"}]
            end

          %HTTPoison.Error{} = e ->
            acc ++ [{:err, dst, nil, HTTPoison.Error.message(e)}]

          # error cases
          retval ->
            acc ++ [{:err, dst, nil, "unknown error: #{inspect(retval)}"}]
        end
      end)

    {:ok, sent}
  end

  def send_webmention(endpoint, source, target) do
    www_source = URI.encode_www_form(source)
    www_target = URI.encode_www_form(target)

    case HTTPoison.post(endpoint, "source=#{www_source}&target=#{www_target}", [
           {"Content-Type", "application/x-www-form-urlencoded"}
         ]) do
      {:ok, response} ->
        case success?(:ok, response) do
          true -> :ok
          _ -> {:error, response.status_code}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Atom.to_string(reason)}
    end
  end

  def discover_endpoint(source_url) do
    {rslt, response} = HTTPoison.get(source_url, [], follow_redirects: true)

    if success?(rslt, response) do
      link = get_link_header(response)
      ctype = get_header(response.headers, "Content-Type")
      is_text = ctype != nil and Regex.match?(~r/text\//, ctype)

      cond do
        link != nil and is_webmention_link(link) ->
          link =
            String.split(link, ",")
            |> Enum.map(fn x -> String.strip(x) end)
            |> Enum.filter(fn x -> is_webmention_link(x) end)
            |> List.first()

          cleaned_link = Regex.replace(~r/^<|>$/, Regex.replace(~r/; rel=.*/, link, ""), "")

          abs_link =
            if is_text do
              abs_uri(cleaned_link, source_url, response.body)
            else
              abs_uri(cleaned_link, source_url, "")
            end

          {:ok, abs_link}

        is_text ->
          mention_link =
            Floki.parse(response.body)
            |> Floki.find("[rel~=webmention]")
            |> List.first()

          if mention_link == nil do
            {:ok, nil}
          else
            {:ok, Floki.attribute(mention_link, "href") |> List.first() |> abs_uri(source_url, response.body)}
          end

        true ->
          {:ok, nil}
      end
    else
      case response do
        %HTTPoison.Response{} ->
          {:error, response.status_code}

        %HTTPoison.Error{} ->
          {:error, HTTPoison.Error.message(response)}

        _ ->
          {:error, "unknown error"}
      end
    end
  end

  def get_link_header(response) do
    val = get_header(response.headers, "Link")

    cond do
      is_bitstring(val) ->
        val

      is_list(val) ->
        Enum.filter(val, fn x -> is_webmention_link(x) end) |> List.first()

      true ->
        nil
    end
  end

  def is_webmention_link(link) do
    Regex.match?(~r/rel="?(http:\/\/webmention\/|webmention)"?/, to_string(link))
  end

  def is_valid_mention(source_url, target_url) do
    {rslt, response} = HTTPoison.get(source_url, [], follow_redirects: true)

    if success?(rslt, response) do
      Floki.parse(response.body)
      |> Floki.find("a, link")
      |> Enum.find(fn x ->
        {tagname, _, _} = x

        target =
          case tagname do
            "a" ->
              Floki.attribute(x, "href") |> List.first()

            _ ->
              Floki.attribute(x, "rel") |> List.first()
          end

        target == target_url
      end) != nil
    else
      false
    end
  end

  def blank?(val) do
    String.strip(to_string(val)) == ""
  end

  def abs_uri(url, base_url, doc) do
    parsed = URI.parse(url)
    parsed_base = URI.parse(base_url)

    cond do
      # absolute URI
      not blank?(parsed.scheme) ->
        url

      # protocol relative URI
      blank?(parsed.scheme) and not blank?(parsed.host) ->
        URI.to_string(%{parsed | scheme: parsed_base.scheme})

      true ->
        base_element = Floki.find(doc, "base")

        new_base =
          if base_element == nil or blank?(Floki.attribute(base_element, "href")) do
            base_url
          else
            abs_uri(Floki.attribute(base_element, "href") |> List.first(), base_url, [])
          end

        parsed_new_base = URI.parse(new_base)

        new_path =
          if parsed.path == "" or parsed.path == nil do
            parsed_new_base.path
          else
            Path.expand(parsed.path || "/", Path.dirname(parsed_new_base.path || "/"))
          end

        URI.to_string(%{parsed | scheme: parsed_new_base.scheme, host: parsed_new_base.host, path: new_path})
    end
  end

  def results_as_html(list) do
    lines =
      Enum.map(list, fn line ->
        case line do
          {:err, dest, nil, reason} ->
            "<strong>ERROR:</strong> #{dest}: #{reason}"

          {:err, dest, endpoint, reason} ->
            "<strong>ERROR:</strong> #{dest}: endpoint #{endpoint}: #{reason}"

          {:ok, dest, endpoint, _} ->
            "<strong>SUCCESS:</strong> #{dest}: sent to endpoint #{endpoint}"
        end
      end)

    "<ul>" <> Enum.join(lines, "<li>") <> "</ul>"
  end

  def results_as_text(list) do
    lines =
      Enum.map(list, fn line ->
        case line do
          {:err, dest, nil, reason} ->
            "ERROR: #{dest}: #{reason}"

          {:err, dest, endpoint, reason} ->
            "ERROR: #{dest}: endpoint #{endpoint}: #{reason}"

          {:ok, dest, endpoint, _} ->
            "SUCCESS: #{dest}: sent to endpoint #{endpoint}"
        end
      end)

    Enum.join(lines, "\n")
  end

  defp success?(:ok, %HTTPoison.Response{status_code: code}) do
    code in 200..299
  end

  defp success?(_, _), do: false

  defp get_header(headers, key) do
    ret =
      headers
      |> Enum.filter(fn {k, _} -> String.downcase(k) == String.downcase(key) end)

    case ret do
      [] ->
        nil

      nil ->
        nil

      _ ->
        hd(ret) |> elem(1)
    end
  end
end
