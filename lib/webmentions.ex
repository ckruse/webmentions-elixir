defmodule Webmentions do
  use Tesla

  alias Webmentions.Utils
  alias Webmentions.Response

  plug(Tesla.Middleware.FollowRedirects, max_redirects: 3)
  plug(Tesla.Middleware.FormUrlencoded)

  @type options :: {:root_selector, String.t()} | {:reject_nofollow, boolean()}

  @default_opts [
    root_selector: ".h-entry",
    reject_nofollow: true
  ]

  @doc """
  Send webmentions to links found on the `source_url` page.

  Options include:
    * root_selector: css class filtering the block where to look for links (default: `.h-entry`)
    * reject_nofollow: doesn't send webmention to links with `rel="nofollow"` attribute (`true` by default)
  """
  @spec send_webmentions(String.t(), String.t() | [options()]) ::
          {:ok, [Response.t()]} | {:error, integer()} | {:error, String.t()}
  def send_webmentions(source_url, opts \\ [])

  def send_webmentions(source_url, root_selector) when is_binary(root_selector) do
    opts = Keyword.merge(@default_opts, root_selector: root_selector)

    case get(source_url) do
      {:ok, response} ->
        if Utils.success?(:ok, response) do
          send_webmentions_for_doc(response.body, source_url, opts)
        else
          {:error, response.status}
        end

      {:error, reason} ->
        {:error, Atom.to_string(reason)}
    end
  end

  def send_webmentions(source_url, opts) when is_list(opts) do
    opts = Keyword.merge(@default_opts, opts)

    case get(source_url) do
      {:ok, response} ->
        if Utils.success?(:ok, response) do
          send_webmentions_for_doc(response.body, source_url, opts)
        else
          {:error, response.status}
        end

      {:error, reason} ->
        {:error, Atom.to_string(reason)}
    end
  end

  @spec send_webmentions_for_doc(String.t(), String.t(), String.t() | [options()]) :: {:ok, [Response.t()]}
  def send_webmentions_for_doc(html, source_url, opts \\ [])

  def send_webmentions_for_doc(html, source_url, root_selector) when is_binary(root_selector) do
    opts = Keyword.merge(@default_opts, root_selector: root_selector)
    document = Floki.parse_document!(html)

    Floki.find(document, root_selector)
    |> extract_links_from_doc(opts)
    |> send_webmentions_for_links(source_url, document)
  end

  def send_webmentions_for_doc(html, source_url, opts) when is_list(opts) do
    opts = Keyword.merge(@default_opts, opts)
    root_selector = Keyword.get(opts, :root_selector)
    document = Floki.parse_document!(html)

    Floki.find(document, root_selector)
    |> extract_links_from_doc(opts)
    |> send_webmentions_for_links(source_url, document)
  end

  @spec send_webmentions_for_links(String.t(), [String.t()]) :: {:ok, [Response.t()]}
  def send_webmentions_for_links(source_url, targets) do
    sent = Enum.map(targets, &handle_send_webmention(source_url, &1))
    {:ok, sent}
  end

  defp send_webmentions_for_links(links, source_url, document) do
    sent = Enum.map(links, &handle_send_webmention(&1, source_url, document))
    {:ok, sent}
  end

  defp handle_send_webmention(link, source, document) do
    target = Floki.attribute(link, "href") |> List.first() |> abs_uri(source, document)
    handle_send_webmention(source, target)
  end

  defp handle_send_webmention(source, target) do
    with {:ok, endpoint} when endpoint != nil and endpoint != "" <- discover_endpoint(target),
         {:ok, body} <- send_webmention(endpoint, source, target) do
      %Response{status: :ok, target: target, endpoint: endpoint, message: "sent", body: body}
    else
      {:ok, nil} ->
        %Response{status: :no_endpoint, target: target, message: "no endpoint found"}

      {:ok, ""} ->
        %Response{status: :no_endpoint, target: target, message: "no endpoint found"}

      {:error, status} when is_number(status) ->
        %Response{status: :error, target: target, http_status: status, message: "Status #{status}"}

      {:error, message} ->
        %Response{status: :error, target: target, message: message}
    end
  end

  @spec send_webmention(String.t(), String.t(), String.t()) ::
          {:error, integer()} | {:error, String.t()} | {:ok, String.t()}
  def send_webmention(endpoint, source, target) do
    case post(endpoint, %{"source" => source, "target" => target}) do
      {:ok, response} ->
        if Utils.success?(:ok, response),
          do: {:ok, response.body},
          else: {:error, response.status}

      {:error, reason} ->
        {:error, Atom.to_string(reason)}
    end
  end

  @spec discover_endpoint(String.t()) :: {:error, String.t()} | {:ok, nil | String.t() | URI.t()}
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
      {:error, reason} -> {:error, reason}
      _ -> {:error, "unknown error"}
    end
  end

  @spec get_link_header(Tesla.Env.t()) :: nil | String.t()
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

  @spec is_webmention_link(String.t()) :: boolean()
  def is_webmention_link(link) do
    Regex.match?(~r/rel="?(http:\/\/webmention\/|webmention)"?/, to_string(link))
  end

  @spec is_valid_mention(String.t(), String.t()) :: boolean()
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

  @spec abs_uri(String.t(), String.t(), String.t() | Floki.html_tree()) :: String.t()
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

  @spec results_as_html([Response.t()]) :: String.t()
  def results_as_html(list) do
    lines =
      Enum.map(list, fn
        %Response{status: :error, message: reason, target: dest, endpoint: endpoint} when not is_nil(endpoint) ->
          "<li><strong>ERROR:</strong> #{dest}: endpoint #{endpoint}: #{reason}</li>"

        %Response{status: status, message: reason, target: dest} when status in [:error, :no_endpoint] ->
          "<li><strong>ERROR:</strong> #{dest}: #{reason}</li>"

        %Response{status: :ok, target: dest, endpoint: endpoint} ->
          "<li><strong>SUCCESS:</strong> #{dest}: sent to endpoint #{endpoint}</li>"
      end)
      |> Enum.join()

    "<ul>#{lines}</ul>"
  end

  @spec results_as_text([Response.t()]) :: String.t()
  def results_as_text(list) do
    list
    |> Enum.map(fn
      %Response{status: :error, message: reason, target: dest, endpoint: endpoint} when not is_nil(endpoint) ->
        "ERROR: #{dest}: endpoint #{endpoint}: #{reason}\n"

      %Response{status: status, message: reason, target: dest} when status in [:error, :no_endpoint] ->
        "ERROR: #{dest}: #{reason}\n"

      %Response{status: :ok, target: dest, endpoint: endpoint} ->
        "SUCCESS: #{dest}: sent to endpoint #{endpoint}\n"
    end)
    |> Enum.join()
  end

  defp get_header(headers, key) do
    ret =
      headers
      |> Enum.filter(fn {k, _} -> String.downcase(k) == String.downcase(key) end)

    if Utils.blank?(ret),
      do: nil,
      else: hd(ret) |> elem(1)
  end

  defp extract_links_from_doc(content, opts) do
    Floki.find(content, "a[href]")
    |> Enum.filter(fn link ->
      case Floki.attribute(link, "href") |> List.first() do
        "/" <> _ -> true
        "http" <> _ -> true
        _ -> false
      end
    end)
    |> maybe_reject_nofollow_links(opts[:reject_nofollow])
  end

  defp maybe_reject_nofollow_links(links, false), do: links

  defp maybe_reject_nofollow_links(links, true) do
    Enum.reject(links, fn link ->
      link
      |> Floki.attribute("rel")
      |> List.first()
      |> to_string
      |> String.contains?("nofollow")
    end)
  end
end
