# Webmentions

A [Webmention](https://indiewebcamp.com/Webmention) module for Elixir.

## Installation

This package is [available in Hex](https://hex.pm/packages/webmentions)

1. Add webmentions to your list of dependencies in `mix.exs`:

   ```elixir
   def deps do
     [{:webmentions, "~> 0.5.0"}]
   end
   ```

## Usage

Just call `Webmentions.send_webmentions("http://example.org/")` where
the URL is the URL of the source document:

    Webmentions.send_webmentions("http://example.org/")

This will give you either

```elixir
{:ok, ["list", "of", "urls"]}
```

where the list contains a list of URLs we sent a webmention to or

```elixir
{:error, reason}
```

If you already know the list of URL mentions, you can skip parsing the 
source URL and send webmentions to all destinations URL (if they support it): 

    destinations = ["http://example.org/", "http://other.org/"]
    Webmentions.send_webmentions_for_urls("https://source.org", destinations)
    
It will behave as `Webmentions.send_webmentions/2` does.

## Dependencies

We need [Floki](https://github.com/philss/floki) for HTML parsing and
[Tesla](https://github.com/teamon/tesla) for HTTP communication.
