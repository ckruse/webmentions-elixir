# Webmentions

A [Webmention](https://indiewebcamp.com/Webmention) module for Elixir.

## Installation

This package is [available in Hex](https://hex.pm/packages/webmentions)

  1. Add webmentions to your list of dependencies in `mix.exs`:

        def deps do
          [{:webmentions, "~> 0.0.2"}]
        end

## Usage

Just call `Webmentions.send_webmentions("http://example.org/")` where
the URL is the URL of the source document:

    Webmentions.send_webmentions("http://example.org/")

This will give you either

    {:ok, ["list", "of", "urls"]}

where the list contains a list of URLs we sent a webmention to or

    {:error, reason}

## Dependencies

We need [Floki](https://github.com/philss/floki) for HTML parsing and
[HTTPotion](https://github.com/myfreeweb/httpotion) for HTTP communication.


