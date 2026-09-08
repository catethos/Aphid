defmodule Consumer.MixProject do
  use Mix.Project
  def project, do: [app: :aphid_consumer, version: "0.0.0", deps: [
    {:aphid, "== 0.1.0-dev"}]]
  def application, do: [extra_applications: [:aphid]]
end
