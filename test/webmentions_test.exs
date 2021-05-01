defmodule WebmentionsTest do
  use ExUnit.Case, async: true
  doctest Webmentions

  import Tesla.Mock

  describe "Webmentions.discover_endpoint/1" do
    test "discovers from a link in header" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html>",
        headers: [{"Link", "<http://example.org/webmentions>; rel=\"webmention\""}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "discovers from a link in header case-insensitive" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html>",
        headers: [{"link", "<http://example.org/webmentions>; rel=\"webmention\""}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "discovers from a link in document" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html><head><link rel=\"webmention\" href=\"http://example.org/webmentions\">",
        headers: [{"Content-Type", "text/html"}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "discovers from multiple links in document" do
      doc = %Tesla.Env{
        status: 200,
        body: """
        <html>
        <head>
        <link rel="webmention" href="http://example.org/webmentions">
        <link rel="micropub" href="http://example.org/micropub">
        <link rel="token_endpoint" href="http://example.org/login">
        <link rel="authorization_endpoint" href="https://indieauth.com/auth">
        <link rel="hub" href="https://switchboard.p3k.io">
        <link rel="self" href="http://example.org">
        """,
        headers: [{"Content-Type", "text/html"}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "discovers from a link list in header" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html>",
        headers: [
          {"Link",
           "<http://example.org/webmentions>; rel=\"webmention\", <http://example.org/micropub>; rel=\"micropub\", <http://example.org/login>; rel=\"token_endpoint\", <https://indieauth.com/auth>; rel=\"authorization_endpoint\", <https://switchboard.p3k.io>; rel=\"hub\", <http://example.org>; rel=\"self\""}
        ]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "discovers from a link list in header when not first element" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html>",
        headers: [
          {"Link",
           "<http://example.org/micropub>; rel=\"micropub\", <http://example.org/login>; rel=\"token_endpoint\", <http://example.org/webmentions>; rel=\"webmention\", <https://indieauth.com/auth>; rel=\"authorization_endpoint\", <https://switchboard.p3k.io>; rel=\"hub\", <http://example.org>; rel=\"self\""}
        ]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end

    test "ignores an empty link in header" do
      doc = %Tesla.Env{status: 200, body: "<html>", headers: [{"Link", ""}]}

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, nil}
    end

    test "resolves an empty link in document to document URL" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html><head><link rel=\"webmention\" href=\"\">",
        headers: [{"Content-Type", "text/html"}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org"}
    end
  end

  describe "Webmentions.send_webmentions/2" do
    test "correctly sends a mention to example.org/webmentions" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html class=\"h-entry\"><a href=\"http://example.org/test\">blah</a>",
        headers: [{"Link", "<http://example.org/webmentions>; rel=\"webmention\""}]
      }

      mock(fn _ -> {:ok, doc} end)

      assert Webmentions.send_webmentions("http://example.org") ==
               {:ok,
                [
                  %Webmentions.Response{
                    status: :ok,
                    target: "http://example.org/test",
                    endpoint: "http://example.org/webmentions",
                    message: "sent",
                    body: "<html class=\"h-entry\"><a href=\"http://example.org/test\">blah</a>"
                  }
                ]}
    end

    test "doesn't send a webmention to a rel=nofollow" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html class=\"h-entry\"><a rel=\"nofollow\" href=\"http://example.org/test\">blah</a>",
        headers: [{"Link", "<http://example.org/webmentions>; rel=\"webmention\""}]
      }

      mock(fn _ -> {:ok, doc} end)
      assert Webmentions.send_webmentions("http://example.org") == {:ok, []}
    end

    test "successfully sends mentions to relative URLs" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html class=\"h-entry\"><a href=\"/test\">blah</a>",
        headers: [{"Link", "<http://example.org/webmentions>; rel=\"webmention\""}]
      }

      mock(fn
        %{method: :get, url: url} ->
          assert url != "/test"
          {:ok, doc}

        %{method: :post} ->
          {:ok, doc}
      end)

      assert Webmentions.send_webmentions("http://example.org") ==
               {:ok,
                [
                  %Webmentions.Response{
                    status: :ok,
                    target: "http://example.org/test",
                    endpoint: "http://example.org/webmentions",
                    message: "sent",
                    body: "<html class=\"h-entry\"><a href=\"/test\">blah</a>"
                  }
                ]}
    end

    test "doesn't send a mention with empty link" do
      doc = %Tesla.Env{
        status: 200,
        body: "<html class=\"h-entry\"><a href=\"http://example.org/test\">blah</a>",
        headers: [{"Link", ""}]
      }

      mock(fn _ -> {:ok, doc} end)

      assert Webmentions.send_webmentions("http://example.org") ==
               {:ok,
                [
                  %Webmentions.Response{
                    status: :no_endpoint,
                    target: "http://example.org/test",
                    endpoint: nil,
                    message: "no endpoint found"
                  }
                ]}
    end
  end

  describe "Webmentions.send_webmentions_for_doc/3" do
    test "successfully mentions a HTTP ressource" do
      mock(fn _ -> %Tesla.Env{status: 200} end)

      assert Webmentions.send_webmentions_for_doc(
               "<html class=\"h-entry\"><a href=\"http://images1.dawandastatic.com/Product/18223/18223505/big/1301969630-83.jpg\">blah</a>",
               "http://example.org/"
             ) ==
               {:ok,
                [
                  %Webmentions.Response{
                    status: :no_endpoint,
                    target: "http://images1.dawandastatic.com/Product/18223/18223505/big/1301969630-83.jpg",
                    endpoint: nil,
                    message: "no endpoint found"
                  }
                ]}
    end
  end

  describe "Webmentions.send_webmentions_for_links/2" do
    test "correctly sends a mention to example.org/webmentions" do
      mock(fn env ->
        case env.url do
          "http://example.org/test" ->
            %Tesla.Env{
              status: 200,
              body: "<html class=\"h-entry\"><a href=\"http://example.org/test\">blah</a>",
              headers: [{"Link", "<http://example.org/webmentions>; rel=\"webmention\""}]
            }

          "http://other.org/test" ->
            %Tesla.Env{
              status: 200,
              body: "<html class=\"h-entry\"><a href=\"http://other.org/test\">other blah</a>",
              headers: [{"Link", "<http://other.org/webmentions>; rel=\"webmention\""}]
            }

          _webmention_endpoint ->
            %Tesla.Env{status: 200}
        end
      end)

      assert Webmentions.send_webmentions_for_links("http://source.org", [
               "http://example.org/test",
               "http://other.org/test"
             ]) ==
               {:ok,
                [
                  %Webmentions.Response{
                    status: :ok,
                    target: "http://example.org/test",
                    endpoint: "http://example.org/webmentions",
                    message: "sent"
                  },
                  %Webmentions.Response{
                    status: :ok,
                    target: "http://other.org/test",
                    endpoint: "http://other.org/webmentions",
                    message: "sent"
                  }
                ]}
    end
  end

  describe "results_as_html/1" do
    test "converts a success list to html" do
      assert Webmentions.results_as_html([
               %Webmentions.Response{status: :ok, endpoint: "http://example.org", target: "http://example.org"}
             ]) ==
               "<ul>" <>
                 "<li><strong>SUCCESS:</strong> http://example.org: sent to endpoint http://example.org</li>" <>
                 "</ul>"
    end

    test "converts an error list to html" do
      assert Webmentions.results_as_html([
               %Webmentions.Response{status: :error, message: "Status 500", target: "http://example.org"},
               %Webmentions.Response{
                 status: :error,
                 message: "foo bar",
                 target: "http://example.org/",
                 endpoint: "http://example.org/"
               }
             ]) ==
               "<ul>" <>
                 "<li><strong>ERROR:</strong> http://example.org: Status 500</li>" <>
                 "<li><strong>ERROR:</strong> http://example.org/: endpoint http://example.org/: foo bar</li>" <>
                 "</ul>"
    end

    test "converts a no endpoint list to html" do
      assert Webmentions.results_as_html([
               %Webmentions.Response{status: :no_endpoint, message: "No Endpoint", target: "http://example.org"}
             ]) ==
               "<ul>" <>
                 "<li><strong>ERROR:</strong> http://example.org: No Endpoint</li>" <>
                 "</ul>"
    end
  end

  describe "results_as_text/1" do
    test "converts a success list to text" do
      assert Webmentions.results_as_text([
               %Webmentions.Response{status: :ok, endpoint: "http://example.org", target: "http://example.org"}
             ]) == "SUCCESS: http://example.org: sent to endpoint http://example.org\n"
    end

    test "converts an error list to html" do
      assert Webmentions.results_as_text([
               %Webmentions.Response{status: :error, message: "Status 500", target: "http://example.org"},
               %Webmentions.Response{
                 status: :error,
                 message: "foo bar",
                 target: "http://example.org/",
                 endpoint: "http://example.org/"
               }
             ]) ==
               "ERROR: http://example.org: Status 500\n" <>
                 "ERROR: http://example.org/: endpoint http://example.org/: foo bar\n"
    end

    test "converts a no endpoint list to html" do
      assert Webmentions.results_as_text([
               %Webmentions.Response{status: :no_endpoint, message: "No Endpoint", target: "http://example.org"}
             ]) == "ERROR: http://example.org: No Endpoint\n"
    end
  end
end
