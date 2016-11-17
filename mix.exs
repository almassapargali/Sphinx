defmodule Sphinx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sphinx,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application, do: []

  defp deps do
    [
      {:plug, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    Sphinx is a authorization library for Phoenix apps.
    """
  end

  defp package do
    [
      name: :sphinx,
      maintainers: ["Almas Sapargali"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/almassapargali/sphinx"
      }
    ]
  end
end
