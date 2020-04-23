defmodule Webmentions do
  use Tesla
  alias Webmentions.Utils

  plug(Tesla.Middleware.FollowRedirects, max_redirects: 3)
  plug(Tesla.Middleware.FormUrlencoded)

  def send_webmentions(source_url, root_selector \\ ".h-entry") do
    case get(source_url) do
      {:ok, response} ->
        if Utils.success?(:ok, response) do
          send_webmentions_for_doc(response.body, source_url, root_selector)
        else
          {:error, response.status}
        end

      {:error, reason} ->
        {:error, Atom.to_string(reason)}
    end
  end

  def send_webmentions_for_doc(html, source_url, root_selector \\ ".h-entry") do
    document = Floki.parse_document!(html)
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

        with {:ok, endpoint} when endpoint != nil and endpoint != "" <- discover_endpoint(dst),
             :ok <- send_webmention(endpoint, source_url, dst) do
          acc ++ [{:ok, dst, endpoint, "sent"}]
        else
          {:ok, nil} -> acc ++ [{:ok, dst, nil, "no endpoint found"}]
          {:ok, ""} -> acc ++ [{:ok, dst, nil, "no endpoint found"}]
          {:error, status} when is_number(status) -> acc ++ [{:err, dst, nil, "Status #{status}"}]
          {:error, message} -> acc ++ [{:err, dst, nil, message}]
        end
      end)

    {:ok, sent}
  end

  def send_webmention(endpoint, source, target) do
    case post(endpoint, %{"source" => source, "target" => target}) do
      {:ok, response} ->
        if Utils.success?(:ok, response),
          do: :ok,
          else: {:error, response.status}

      {:error, reason} ->
        {:error, Atom.to_string(reason)}
    end
  end

  def discover_endpoint(source_url) do
    with {:ok, response} <- get(source_url),
         true <- Utils.success?(:ok, response) do
      link = get_link_header(response)
      ctype = get_header(response.headers, "Content-Type")
      is_text = ctype != nil and Regex.match?(~r/text\//, ctype)

      cond do
        link != nil and is_webmention_link(link) ->
          link =
            String.split(link, ",")
            |> Enum.map(fn x -> String.trim(x) end)
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
            Floki.parse_document!(response.body)
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
      %Tesla.Env{status: code} -> {:error, code}
      {:error, reason} -> {:error, Atom.to_string(reason)}
      _ -> {:error, "unknown error"}
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
    with {:ok, response} <- get(source_url),
         true <- Utils.success?(:ok, response) do
      Floki.parse_document!(response.body)
      |> Floki.find("a, link")
      |> Enum.find(fn {tagname, _, _} = node ->
        target =
          case tagname do
            "a" ->
              Floki.attribute([node], "href") |> List.first()

            _ ->
              Floki.attribute([node], "rel") |> List.first()
          end

        target == target_url
      end) != nil
    else
      _ -> false
    end
  end

  def abs_uri(url, base_url, doc) when is_bitstring(doc),
    do: abs_uri(url, base_url, Floki.parse_document!(doc))

  def abs_uri(url, base_url, doc) do
    parsed = URI.parse(url)
    parsed_base = URI.parse(base_url)

    cond do
      # absolute URI
      not Utils.blank?(parsed.scheme) ->
        url

      # protocol relative URI
      Utils.blank?(parsed.scheme) and not Utils.blank?(parsed.host) ->
        URI.to_string(%{parsed | scheme: parsed_base.scheme})

      true ->
        base_element = Floki.find(doc, "base")

        new_base =
          if Utils.blank?(base_element) or Utils.blank?(Floki.attribute(base_element, "href")) do
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

  defp get_header(headers, key) do
    ret =
      headers
      |> Enum.filter(fn {k, _} -> String.downcase(k) == String.downcase(key) end)

    if Utils.blank?(ret),
      do: nil,
      else: hd(ret) |> elem(1)
  end
end
