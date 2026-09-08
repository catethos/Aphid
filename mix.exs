Code.require_file("mix/aphid_bundle.exs", __DIR__)

defmodule Aphid.MixProject do
  use Mix.Project

  def project do
    [
      app: :aphid,
      compilers: [:aphid_bundle] ++ Mix.compilers(),
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      source_url: "https://github.com/catethos/Aphid",
      deps: [{:zigler, "== 0.16.0", runtime: false}, {:telemetry, "~> 1.3"}],
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/catethos/Aphid"},
        files: [
          "mix.exs",
          "mix.lock",
          "mix/*.exs",
          "lib/**/*.ex",
          "README.md",
          "LICENSE",
          "THIRD_PARTY.md",
          "docs/*.md",
          "native/lock.json",
          "native/local-bundle.json",
          "native/aphid_nif.zig",
          "native/bridge.h",
          "native/bridge.cpp",
          "native/CMakeLists.txt",
          "native/patches/*.patch",
          "scripts/build.py",
          "scripts/proof.py",
          "scripts/source_preflight.py",
          "native/proof.zig",
          "native/proof.h",
          "native/proof.cpp"
        ]
      ],
      description: "LadybugDB for Elixir through Zigler"
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto], mod: {Aphid.Application, []}]
end
