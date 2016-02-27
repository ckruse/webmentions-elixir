defmodule WebmentionsTest do
  use ExUnit.Case
  doctest Webmentions

  import Mock

  test "discovers from a link in header" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/webmentions>; rel=\"webmention\""]}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end] do
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end    
  end

  test "discovers from a link in document" do
    doc = %HTTPotion.Response{status_code: 200,
                              body: "<html><head><link rel=\"webmention\" href=\"http://example.org/webmentions\">",
                              headers: %HTTPotion.Headers{hdrs: []}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end] do
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end
  end

  test "discovers from multiple links in document" do
    doc = %HTTPotion.Response{status_code: 200,
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
                              headers: %HTTPotion.Headers{hdrs: []}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end] do
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end
  end

  test "discovers from a link list in header" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/webmentions>; rel=\"webmention\", <http://example.org/micropub>; rel=\"micropub\", <http://example.org/login>; rel=\"token_endpoint\", <https://indieauth.com/auth>; rel=\"authorization_endpoint\", <https://switchboard.p3k.io>; rel=\"hub\", <http://example.org>; rel=\"self\""]}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end] do
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end
  end

  test "discovers from a link list in header when not first element" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/micropub>; rel=\"micropub\", <http://example.org/login>; rel=\"token_endpoint\", <http://example.org/webmentions>; rel=\"webmention\", <https://indieauth.com/auth>; rel=\"authorization_endpoint\", <https://switchboard.p3k.io>; rel=\"hub\", <http://example.org>; rel=\"self\""]}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end] do
      assert Webmentions.discover_endpoint("http://example.org") == {:ok, "http://example.org/webmentions"}
    end
  end

  test "correctly sends a mention to example.org/webmentions" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html class=\"h-entry\"><a href=\"http://example.org/test\">blah</a>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/webmentions>; rel=\"webmention\""]}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end,
                         post: fn(_url, _opts) -> doc end] do
      assert Webmentions.send_webmentions("http://example.org") == {:ok, ["http://example.org/webmentions"]}
    end

  end

  test "doesn't send a webmention to a rel=nofollow" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html class=\"h-entry\"><a rel=\"nofollow\" href=\"http://example.org/test\">blah</a>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/webmentions>; rel=\"webmention\""]}}

    with_mock HTTPotion, [get: fn(_url, _opts) -> doc end,
                         post: fn(_url, _opts) -> doc end] do
      assert Webmentions.send_webmentions("http://example.org") == {:ok, []}
    end
  end

  test "successfully sends mentions to relative URLs" do
    doc = %HTTPotion.Response{status_code: 200, body: "<html class=\"h-entry\"><a href=\"/test\">blah</a>",
                              headers: %HTTPotion.Headers{hdrs: [link: "<http://example.org/webmentions>; rel=\"webmention\""]}}

    with_mock HTTPotion, [get: fn(url, _opts) ->
                           assert url != "/test"
                           doc
                         end,
                         post: fn(_url, _opts) -> doc end] do
      assert Webmentions.send_webmentions("http://example.org") == {:ok, ["http://example.org/webmentions"]}
    end
  end

end
