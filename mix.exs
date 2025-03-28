defmodule Webmentions.Mixfile do
  use Mix.Project

  def project do
    [
      app: :webmentions,
      version: "3.0.1",
      elixir: "~> 1.14",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger]]
  end

  def description do
    """
    A Webmentions (https://indiewebcamp.com/Webmention) module for Elixir
    """
  end

  def package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Christian Kruse"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ckruse/webmentions-elixir"}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:tesla, "~> 1.14.0"},
      {:floki, "~> 0.23"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
