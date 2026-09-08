defmodule Aphid.BundleLoader do
  @moduledoc false

  defmacro __before_compile__(env) do
    hashes =
      if receipt = System.get_env("APHID_BUNDLE_RECEIPT") do
        receipt |> File.read!() |> JSON.decode!() |> Map.fetch!("files")
      end

    quote do
      defoverridable __load_nifs__: 0

      def __load_nifs__ do
        # Embedded boot runs on_load handlers before crypto's NIF is ready.
        # Leave only managed stubs until Aphid.Application verifies and activates.
        if unquote(hashes != nil) and :code.get_mode() == :embedded and
             not :erlang.function_exported(:crypto, :hash, 2) do
          :persistent_term.put({Aphid.BundleLoader, __MODULE__}, true)
          :ok
        else
          directory = Path.join(:code.priv_dir(:aphid), "lib")

          with :ok <- Aphid.BundleLoader.verify(directory, unquote(Macro.escape(hashes))) do
            path = Path.join(directory, unquote(Atom.to_string(env.module)))

            case :erlang.load_nif(String.to_charlist(path), 0) do
              :ok ->
                :ok

              {:error, reason} ->
                require Logger

                Logger.error(
                  "Aphid artifact [unloadable]: #{path}: #{inspect(reason)}; use the matching complete bundle and runtime. No source fallback."
                )

                {:error, reason}
            end
          end
        end
      end
    end
  end

  def activate(module) do
    with {:module, ^module} <- Code.ensure_loaded(module) do
      key = {__MODULE__, module}

      if :persistent_term.get(key, false) do
        case module.__load_nifs__() do
          :ok ->
            :persistent_term.erase(key)
            :ok

          error ->
            error
        end
      else
        :ok
      end
    end
  end

  def verify(_directory, nil), do: :ok

  def verify(directory, hashes) do
    Enum.reduce_while(hashes, :ok, fn {name, hash}, :ok ->
      path = Path.join(directory, name)

      case File.read(path) do
        {:ok, bytes} ->
          if Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == hash do
            {:cont, :ok}
          else
            {:halt, failure(:corrupt, path)}
          end

        {:error, _} ->
          {:halt, failure(:missing, path)}
      end
    end)
  end

  defp failure(kind, path) do
    require Logger

    Logger.error(
      "Aphid artifact [#{kind}]: #{path}; reinstall the complete pinned bundle. No source fallback."
    )

    {:error, {kind, path}}
  end
end
