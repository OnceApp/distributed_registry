defmodule DistributedRegistry.MixProject do
  use Mix.Project

  def project do
    [
      app: :distributed_registry,
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      source_url: "https://github.com/OnceApp/distributed_registry"
    ]
  end

  defp description() do
    "Distributed registry"
  end

  defp package() do
    [
      name: "analytics",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      links: %{"Github" => "https://github.com/OnceApp/distributed_registry"},
      licenses: ["MIT"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {:application_starter, [DistributedRegistry.Application, [Mix.env()]]},
      start_phases: [sync: []]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libcluster, "~> 3.0"},
      {:libcluster_ec2, "~> 0.4"},
      {:gen_state_machine, "~> 2.0"},
      {:earmark, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.19.3", only: :dev},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false}
    ]
  end
end
