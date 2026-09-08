defmodule Mix.Tasks.Compile.AphidBundle do
  use Mix.Task.Compiler
  @moduledoc false

  def run(_) do
    archive = System.get_env("APHID_BUNDLE_ARCHIVE")
    digest = System.get_env("APHID_BUNDLE_SHA256")

    case {System.get_env("APHID_INSTALL"), archive, digest} do
      {nil, nil, nil} ->
        source()

      {"source", nil, nil} ->
        source()

      {mode, _, _} when mode in [nil, "precompiled"] ->
        for key <- ~w(ZIGLER_PRECOMPILE_FORCE_RECOMPILE ZIGLER_PRECOMPILED_FORCE_RELOAD) do
          if System.get_env(key, "false") != "false",
            do: fail("selection", "unset #{key}; local bundle mode never falls back to source")
        end

        install(archive, digest, Path.join(Mix.Project.app_path(), "priv"))
        {:ok, []}

      _ ->
        fail(
          "selection",
          "use APHID_INSTALL=precompiled with archive and SHA256, or explicit source without bundle inputs"
        )
    end
  end

  def install(archive, digest, destination) do
    unless is_binary(archive) and File.regular?(archive),
      do: fail("missing", "set APHID_BUNDLE_ARCHIVE to an existing local .tar.gz")

    unless is_binary(digest) and Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, digest),
      do: fail("corrupt", "set APHID_BUNDLE_SHA256 to an independently trusted 64-digit SHA256")

    identity = File.read!(Path.expand("../native/local-bundle.json", __DIR__)) |> JSON.decode!()

    Enum.each(identity["native_sources"], fn {name, expected} ->
      unless sha(File.read!(Path.expand("../native/" <> name, __DIR__))) == expected,
        do:
          fail(
            "incompatible-engine",
            "native interface source #{name} changed; rebuild and review a matching bundle identity"
          )
    end)

    bytes = File.read!(archive)

    unless sha(bytes) == String.downcase(digest),
      do: fail("corrupt", "archive SHA256 mismatch; obtain the pinned archive again")

    table = tar(:table, bytes, [:compressed, :verbose])

    names =
      Enum.map(table, fn {name, type, _, _, _, _, _} ->
        name = List.to_string(name)

        unless type in [:regular, :directory] and safe?(name),
          do:
            fail(
              "unsafe",
              "archive contains a link, special file or unsafe path: #{inspect(name)}"
            )

        name
      end)

    folded = Enum.map(names, &String.downcase/1)

    unless Enum.uniq(folded) == folded,
      do: fail("unsafe", "duplicate or case-colliding archive member")

    regular =
      for {name, :regular, _, _, _, _, _} <- table,
          do: name |> List.to_string() |> String.downcase()

    if Enum.any?(folded, fn name -> Enum.any?(regular, &String.starts_with?(name, &1 <> "/")) end),
       do: fail("unsafe", "archive file is also used as a directory")

    files =
      tar(:extract, bytes, [:compressed, :memory])
      |> Map.new(fn {n, b} -> {List.to_string(n), b} end)

    manifest = json(files, "manifest.json")

    unless manifest["target"] == "aarch64-macos" and :os.type() == {:unix, :darwin},
      do:
        fail(
          "unsupported-target",
          "this local adapter accepts only aarch64-macos bundles on macOS"
        )

    unless String.starts_with?(
             List.to_string(:erlang.system_info(:system_architecture)),
             "aarch64"
           ),
           do: fail("wrong-architecture", "use an ARM64 BEAM and ARM64 artifact")

    unless manifest["native_lock_sha256"] == identity["native_lock_sha256"] and
             manifest["native_lock_sha256"] ==
               sha(File.read!(Path.expand("../native/lock.json", __DIR__))),
           do:
             fail(
               "incompatible-engine",
               "native lock differs; obtain the bundle for this Aphid source package"
             )

    unless Map.new(Map.delete(files, "manifest.json"), fn {n, b} -> {n, sha(b)} end) ==
             manifest["files"],
           do: fail("corrupt", "content manifest mismatch; obtain the pinned archive again")

    candidate = json(files, "candidate.json")

    unless is_list(candidate["flags"]) and
             "-Dtarget=aarch64-macos.13.3-none" in candidate["flags"] and
             "-Dcpu=baseline" in candidate["flags"],
           do: fail("unsupported-target", "expected the explicit macOS 13.3 / baseline candidate")

    unless :erlang.system_info(:version) == ~c"17.0.4" and System.version() == "1.20.0",
      do:
        fail(
          "unsupported-target",
          "local validation currently requires Elixir 1.20.0 / ERTS 17.0.4 (OTP 29.0.4); other runtime gates remain open"
        )

    prefix = "lib/aphid-0.1.0-dev/priv/lib/"
    closure = ~w(Elixir.Aphid.Native.so Elixir.Aphid.Proof.so libaphid_bridge.dylib liblbug.dylib)

    native =
      Map.new(closure, fn name ->
        bytes =
          files[prefix <> name] ||
            fail("missing", "bundle lacks #{name}; obtain the complete 0.1.0-dev bundle")

        case bytes do
          <<0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0, 0, 1, _::binary>> ->
            :ok

          <<0xCF, 0xFA, 0xED, 0xFE, _::binary>> ->
            fail("wrong-architecture", "#{name} is not ARM64")

          _ ->
            fail("unloadable", "#{name} is not a Mach-O library; obtain a valid native bundle")
        end

        {name, bytes}
      end)

    unless Enum.sort(Enum.filter(Map.keys(files), &String.starts_with?(&1, prefix))) ==
             Enum.sort(Enum.map(closure, &(prefix <> &1))),
           do: fail("corrupt", "unexpected native closure members")

    hashes = Map.new(native, fn {n, b} -> {n, sha(b)} end)

    unless hashes == identity["native_files"],
      do:
        fail(
          "incompatible-engine",
          "native fingerprint differs from this package's reviewed local-bundle.json; use the matching candidate"
        )

    # Extract into memory first. Only fixed native names and validated license paths
    # are written into a fresh directory; archive BEAM files are never installed.
    File.mkdir_p!(Path.dirname(destination))
    staging = destination <> ".aphid-" <> Integer.to_string(System.unique_integer([:positive]))
    File.mkdir!(staging)
    File.mkdir!(Path.join(staging, "lib"))
    Enum.each(native, fn {n, b} -> File.write!(Path.join([staging, "lib", n]), b) end)

    Enum.each(files, fn {n, b} ->
      if String.starts_with?(n, "licenses/") do
        path = Path.join(staging, n)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, b)
      end
    end)

    receipt =
      JSON.encode!(%{archive_sha256: String.downcase(digest), files: hashes, identity: identity})

    File.write!(Path.join(staging, "aphid-bundle.json"), receipt)

    if match?({:ok, %File.Stat{type: :symlink}}, File.lstat(destination)),
      do: fail("unsafe", "installation destination is a symlink; use an empty MIX_BUILD_PATH")

    if File.exists?(destination) do
      # Never overwrite an unrelated/native development priv or follow its symlink.
      unless File.read(Path.join(destination, "aphid-bundle.json")) == {:ok, receipt},
        do:
          fail(
            "selection",
            "destination contains another installation; use an empty MIX_BUILD_PATH"
          )

      Enum.each(hashes, fn {n, h} ->
        path = Path.join([destination, "lib", n])

        unless File.regular?(path),
          do: fail("missing", "installed #{n} is absent; use an empty MIX_BUILD_PATH")

        unless sha(File.read!(path)) == h,
          do: fail("corrupt", "installed #{n} changed; use an empty MIX_BUILD_PATH")
      end)

      File.rm_rf!(staging)
    else
      File.rename!(staging, destination)
    end

    for name <- ["Native", "Proof"] do
      System.put_env(
        "APHID_#{String.upcase(name)}_PRECOMPILED",
        Path.join([destination, "lib", "Elixir.Aphid.#{name}.so"])
      )
    end

    System.put_env("APHID_BUNDLE_RECEIPT", Path.join(destination, "aphid-bundle.json"))

    Mix.shell().info(
      "Aphid local bundle verified and installed: SHA256 #{String.downcase(digest)}"
    )
  end

  defp source do
    if File.exists?(Path.join([Mix.Project.app_path(), "priv", "aphid-bundle.json"])),
      do:
        fail(
          "selection",
          "this build contains a local bundle; keep its archive/checksum selection or use an empty source build path"
        )

    System.delete_env("APHID_BUNDLE_RECEIPT")
    {:noop, []}
  end

  defp safe?(name),
    do:
      Regex.match?(~r/\A[A-Za-z0-9_.\/+\-]+\z/, name) and
        Enum.all?(String.split(name, "/"), &(&1 not in ["", ".", ".."]))

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp json(files, name) do
    case JSON.decode(files[name] || "") do
      {:ok, value} when is_map(value) -> value
      _ -> fail("corrupt", "missing or invalid #{name}")
    end
  end

  defp tar(action, bytes, options) do
    case apply(:erl_tar, action, [{:binary, bytes}, options]) do
      {:ok, value} -> value
      {:error, reason} -> fail("corrupt", "invalid tar archive: #{inspect(reason)}")
    end
  end

  defp fail(kind, detail),
    do: Mix.raise("Aphid artifact [#{kind}]: #{detail}. No source fallback.")
end
