defmodule Aphid.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    with :ok <- Aphid.BundleLoader.activate(Aphid.Native),
         :ok <- Aphid.BundleLoader.activate(Aphid.Proof) do
      Supervisor.start_link([], strategy: :one_for_one)
    end
  end
end
