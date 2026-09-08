Mix.start()

defmodule DefaultSelectionProject do
  use Mix.Project
  def project, do: [app: :default_selection_proof, version: "0.1.2-dev"]
end

work = Path.join(System.tmp_dir!(), "aphid-default-#{System.unique_integer([:positive])}")
File.mkdir_p!(Path.join(work, "mix"))
File.mkdir_p!(Path.join(work, "native"))

for name <- ["local-bundle.json", "linux-bundles.json"] do
  catalog = File.read!(Path.expand("../native/#{name}", __DIR__)) |> JSON.decode!()

  # The missing-default cases need disabled fixture URLs, even after publication.
  disabled =
    if name == "local-bundle.json",
      do: Map.delete(catalog, "url"),
      else: Map.new(catalog, fn {target, pin} -> {target, Map.delete(pin, "url")} end)

  File.write!(Path.join(work, "native/#{name}"), JSON.encode!(disabled))
end

File.cp!(Path.expand("../mix/aphid_bundle.exs", __DIR__), Path.join(work, "mix/aphid_bundle.exs"))
Code.require_file(Path.join(work, "mix/aphid_bundle.exs"))

reject = fn kind, fun ->
  try do
    fun.()
    raise "accepted #{kind} fixture"
  rescue
    e in Mix.Error ->
      true = String.contains?(e.message, "[#{kind}]")
      true = String.contains?(e.message, "No source fallback")
      IO.puts(e.message)
  end
end

for key <-
      ~w(APHID_INSTALL APHID_BUNDLE_ARCHIVE APHID_BUNDLE_URL APHID_BUNDLE_SHA256 ZIGLER_PRECOMPILE_FORCE_RECOMPILE ZIGLER_PRECOMPILED_FORCE_RELOAD) do
  System.delete_env(key)
end

reject.("missing", fn -> Mix.Tasks.Compile.AphidBundle.run([]) end)
System.put_env("APHID_INSTALL", "precompiled")
reject.("missing", fn -> Mix.Tasks.Compile.AphidBundle.run([]) end)

for {os, arch} <- [
      {{:unix, :darwin}, "x86_64-apple-darwin"},
      {{:unix, :linux}, "x86_64-unknown-linux-musl"},
      {{:win32, :nt}, "aarch64"}
    ] do
  reject.("unsupported-target", fn ->
    Mix.Tasks.Compile.AphidBundle.default_bundle("0.1.2-dev", os, arch)
  end)
end

for {file, os, arch, target} <- [
      {"local-bundle.json", {:unix, :darwin}, "aarch64-apple-darwin25.0", nil},
      {"linux-bundles.json", {:unix, :linux}, "x86_64-pc-linux-gnu", "x86_64-linux-gnu"},
      {"linux-bundles.json", {:unix, :linux}, "aarch64-unknown-linux-gnu", "aarch64-linux-gnu"}
    ] do
  path = Path.join(work, "native/#{file}")
  catalog = File.read!(path) |> JSON.decode!()
  pin = if target, do: catalog[target], else: catalog
  url = "https://github.com/catethos/Aphid/releases/download/v0.1.2-dev/#{pin["archive"]}"
  updated = Map.put(pin, "url", url)
  File.write!(path, JSON.encode!(if target, do: Map.put(catalog, target, updated), else: updated))
  {^url, digest} = Mix.Tasks.Compile.AphidBundle.default_bundle("0.1.2-dev", os, arch)
  true = digest == pin["sha256"]

  reject.("incompatible-engine", fn ->
    Mix.Tasks.Compile.AphidBundle.default_bundle("0.2.0", os, arch)
  end)

  bad = Map.put(updated, "sha256", "bad")
  File.write!(path, JSON.encode!(if target, do: Map.put(catalog, target, bad), else: bad))

  reject.("corrupt", fn -> Mix.Tasks.Compile.AphidBundle.default_bundle("0.1.2-dev", os, arch) end)

  File.write!(path, JSON.encode!(catalog))
end

System.put_env("APHID_BUNDLE_SHA256", String.duplicate("0", 64))
reject.("missing", fn -> Mix.Tasks.Compile.AphidBundle.run([]) end)
System.delete_env("APHID_BUNDLE_SHA256")
System.put_env("ZIGLER_PRECOMPILE_FORCE_RECOMPILE", "true")
reject.("selection", fn -> Mix.Tasks.Compile.AphidBundle.run([]) end)
false = Code.ensure_loaded?(Aphid.Native)
false = Code.ensure_loaded?(Aphid.Proof)
File.rm_rf!(work)

IO.puts(
  "Three-target package-pinned selection, disabled defaults, version/pin/target rejection and no native load passed. No download performed."
)
