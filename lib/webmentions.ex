defmodule Webmentions do
  def send_webmentions(source_url, root_selector \\ ".h-entry") do
    response = HTTPotion.get(source_url, [ follow_redirects: true ])

    if HTTPotion.Response.success?(response) do
      send_webmentions_for_doc(response.body, source_url, root_selector)
    else
      {:error, response.status_code}
    end

  rescue
    e ->
      {:error, e.message}
  end

  def send_webmentions_for_doc(html, source_url, root_selector \\ ".h-entry") do
    document = Floki.parse(html)
    content = Floki.find(document, root_selector)
    links = Floki.find(content, "a[href]") |>
      Enum.filter(fn(x) ->
        s = Floki.attribute(x, "rel") |>
          List.first |>
          to_string
        not String.contains?(s, "nofollow")
      end)

    sent = Enum.reduce(links, [], fn(link, acc) ->
      dst = Floki.attribute(link, "href") |> List.first |> abs_uri(source_url, document)

      case discover_endpoint(dst) do
        {:ok, nil} ->
          acc
        {:error, _} ->
          acc
        {:ok, endpoint} ->
          if send_webmention(endpoint, source_url, dst) == :ok do
            acc ++ [endpoint]
          else
            acc
          end
        _ -> # error cases
          acc
      end
    end)

    {:ok, sent}
  end

  def send_webmention(endpoint, source, target) do
    response = HTTPotion.post(endpoint, [body: 'source=#{source}&target=#{target}',
                                         headers: ["Content-Type": "application/x-www-form-urlencoded"]])
    case HTTPotion.Response.success?(response) do
      true -> :ok
      _ -> :error
    end
  end

  def discover_endpoint(source_url) do
    response = HTTPotion.get(source_url, [ follow_redirects: true ])

    if HTTPotion.Response.success?(response) do
      link = get_link_header(response)
      is_text = response.headers[:"Content-Type"] != nil and Regex.match?(~r/text\//, response.headers[:"Content-Type"])

      cond do
        link != nil and is_webmention_link(link) ->
          link = String.split(link, ",") |>
            Enum.map(fn(x) -> String.strip(x) end) |>
            Enum.filter(fn(x) -> is_webmention_link(x) end) |>
            List.first

          cleaned_link = Regex.replace(~r/^<|>$/, Regex.replace(~r/; rel=.*/, link, ""), "")
          abs_link = if is_text do
            abs_uri(cleaned_link, source_url, response.body)
          else
            abs_uri(cleaned_link, source_url, "")
          end

          {:ok, abs_link}

        is_text ->
          mention_link = Floki.parse(response.body) |>
            Floki.find("[rel~=webmention]") |>
            List.first

          if mention_link == nil do
            {:ok, nil}
          else
            {:ok, Floki.attribute(mention_link, "href") |> List.first |> abs_uri(source_url, response.body)}
          end

        true ->
          {:ok, nil}
      end
    else
      {:error, response.status_code}
    end
  rescue
    e ->
      e
  end

  def get_link_header(response) do
    val = response.headers[:"Link"]
    cond do
      is_bitstring(val) ->
        val
      is_list(val) ->
        Enum.filter(val, fn(x) -> is_webmention_link(x) end) |> List.first
      true ->
        nil
    end
  end

  def is_webmention_link(link) do
    Regex.match?(~r/rel="?(http:\/\/webmention\/|webmention)"?/, to_string(link))
  end

  def is_valid_mention(source_url, target_url) do
    response = HTTPotion.get(source_url, [ follow_redirects: true ])

    if HTTPotion.Response.success?(response) do
      Floki.parse(response.body) |>
        Floki.find("a, link") |>
        Enum.find(fn(x) ->
          {tagname, _, _} = x
          target = case tagname do
                     "a" ->
                       Floki.attribute(x, "href") |> List.first
                     _ ->
                       Floki.attribute(x, "rel") |> List.first
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
      not blank?(parsed.scheme) -> # absolute URI
        url
      blank?(parsed.scheme) and not blank?(parsed.host) -> # protocol relative URI
        URI.to_string(%{parsed | scheme: parsed_base.scheme})
      true ->
        base_element = Floki.find(doc, "base")

        new_base = if base_element == nil or blank?(Floki.attribute(base_element, "href")) do
          base_url
        else
          abs_uri(Floki.attribute(base_element, "href") |> List.first,
                  base_url, [])
        end

        parsed_new_base = URI.parse(new_base)
        new_path = if parsed.path == "" or parsed.path == nil do
          parsed_new_base.path
        else
          Path.expand(parsed.path || "/", Path.dirname(parsed_new_base.path || "/"))
        end

        URI.to_string(%{parsed | scheme: parsed_new_base.scheme, host: parsed_new_base.host, path: new_path})
    end
  end

end
