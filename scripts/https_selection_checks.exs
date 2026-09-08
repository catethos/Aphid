Mix.start()
Code.require_file("../mix/aphid_bundle.exs", __DIR__)

defmodule HttpsSelectionProject do
  use Mix.Project
  def project, do: [app: :https_selection_proof, version: "0.1.0-dev"]
end

for {mode, archive, url} <- [
      {"precompiled", "/absent.tar.gz", "https://example.invalid/bundle.tar.gz"},
      {"source", nil, "https://example.invalid/bundle.tar.gz"},
      {"invalid", nil, "https://example.invalid/bundle.tar.gz"}
    ] do
  for key <- ~w(APHID_INSTALL APHID_BUNDLE_ARCHIVE APHID_BUNDLE_URL APHID_BUNDLE_SHA256) do
    System.delete_env(key)
  end

  System.put_env("APHID_INSTALL", mode)
  System.put_env("APHID_BUNDLE_URL", url)
  System.put_env("APHID_BUNDLE_SHA256", String.duplicate("0", 64))
  if archive, do: System.put_env("APHID_BUNDLE_ARCHIVE", archive)

  try do
    Mix.Tasks.Compile.AphidBundle.run([])
    raise "selection conflict accepted"
  rescue
    error in Mix.Error ->
      true = String.contains?(error.message, "[selection]")
      true = String.contains?(error.message, "No source fallback")
      IO.puts(error.message)
  end
end

for key <- ~w(APHID_INSTALL APHID_BUNDLE_ARCHIVE APHID_BUNDLE_URL APHID_BUNDLE_SHA256) do
  System.delete_env(key)
end

try do
  Mix.Tasks.Compile.AphidBundle.run([])
  raise "implicit source mode accepted"
rescue
  error in Mix.Error ->
    true = String.contains?(error.message, "[missing]")
    true = String.contains?(error.message, "APHID_INSTALL=source")
    IO.puts(error.message)
end

System.put_env("APHID_INSTALL", "source")
{:noop, []} = Mix.Tasks.Compile.AphidBundle.run([])
false = Code.ensure_loaded?(Aphid.Native)
false = Code.ensure_loaded?(Aphid.Proof)
IO.puts("HTTPS selection conflicts rejected before native module load")
