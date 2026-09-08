defmodule Mix.Tasks.Compile.AphidBundle do
  use Mix.Task.Compiler
  @moduledoc false

  def run(_) do
    archive = System.get_env("APHID_BUNDLE_ARCHIVE")
    digest = System.get_env("APHID_BUNDLE_SHA256")
    url = System.get_env("APHID_BUNDLE_URL")

    case {System.get_env("APHID_INSTALL"), archive, digest, url} do
      {"source", nil, nil, nil} ->
        source()

      {mode, _, _, _} when mode in [nil, "precompiled"] ->
        for key <- ~w(ZIGLER_PRECOMPILE_FORCE_RECOMPILE ZIGLER_PRECOMPILED_FORCE_RELOAD) do
          if System.get_env(key, "false") != "false",
            do: fail("selection", "unset #{key}; local bundle mode never falls back to source")
        end

        destination = Path.join(Mix.Project.app_path(), "priv")

        cond do
          archive == nil and url == nil and digest == nil ->
            {default_url, default_digest} = default_bundle(Mix.Project.config()[:version])
            install_url(default_url, default_digest, destination)

          archive != nil and url != nil ->
            fail("selection", "set only one of APHID_BUNDLE_ARCHIVE and APHID_BUNDLE_URL")

          url != nil ->
            install_url(url, digest, destination)

          true ->
            install(archive, digest, destination)
        end

        {:ok, []}

      _ ->
        fail(
          "selection",
          "use APHID_INSTALL=precompiled with archive or HTTPS URL and SHA256, or explicit source without bundle inputs"
        )
    end
  end

  # A URL is added to the package identity only after separately authorized delivery.
  # Explicit archive/URL inputs continue to require an independent caller-supplied pin.
  def default_bundle(
        version,
        os \\ :os.type(),
        architecture \\ :erlang.system_info(:system_architecture)
      ) do
    architecture = to_string(architecture)

    identity =
      case {os, architecture} do
        {{:unix, :darwin}, "aarch64" <> _} ->
          File.read!(Path.expand("../native/local-bundle.json", __DIR__)) |> JSON.decode!()

        {{:unix, :linux}, arch}
        when arch in ["x86_64-pc-linux-gnu", "aarch64-unknown-linux-gnu"] ->
          target =
            if String.starts_with?(arch, "x86_64"),
              do: "x86_64-linux-gnu",
              else: "aarch64-linux-gnu"

          catalog =
            File.read!(Path.expand("../native/linux-bundles.json", __DIR__)) |> JSON.decode!()

          catalog[target] || fail("unsupported-target", "no reviewed #{target} identity")

        _ ->
          fail(
            "unsupported-target",
            "no default bundle for this OS/BEAM architecture/libc; use a reviewed explicit archive or explicit source prerequisites"
          )
      end

    unless identity["package_version"] == version,
      do: fail("incompatible-engine", "default bundle version differs from this source package")

    unless is_binary(identity["url"]),
      do:
        fail(
          "missing",
          "this development version has no authorized default delivery; select a pinned archive or HTTPS URL, or set APHID_INSTALL=source with its build prerequisites"
        )

    validate_digest(identity["sha256"])
    {identity["url"], identity["sha256"]}
  end

  def install(archive, digest, destination) do
    unless is_binary(archive) and File.regular?(archive),
      do: fail("missing", "set APHID_BUNDLE_ARCHIVE to an existing local .tar.gz")

    install_bytes(File.read!(archive), digest, destination)
  end

  def install_url(url, digest, destination) do
    uri = URI.parse(url)

    unless uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
             uri.userinfo == nil and uri.fragment == nil,
           do:
             fail(
               "download",
               "APHID_BUNDLE_URL must be an HTTPS URL without credentials or fragment"
             )

    validate_digest(digest)

    case Mix.Utils.read_path(url, timeout: 60_000) do
      {:ok, bytes} ->
        install_bytes(bytes, digest, destination)

      error ->
        fail(
          "download",
          "could not download bundle: #{inspect(error)}; check the URL, network and CA certificates"
        )
    end
  end

  defp validate_digest(digest) do
    unless is_binary(digest) and Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, digest),
      do: fail("corrupt", "set APHID_BUNDLE_SHA256 to an independently trusted 64-digit SHA256")
  end

  defp install_bytes(bytes, digest, destination) do
    validate_digest(digest)

    architecture = List.to_string(:erlang.system_info(:system_architecture))
    linux? = :os.type() == {:unix, :linux}

    host_target =
      cond do
        :os.type() == {:unix, :darwin} ->
          "aarch64-macos"

        linux? and String.starts_with?(architecture, "x86_64") ->
          "x86_64-linux-gnu"

        linux? and String.starts_with?(architecture, "aarch64") ->
          "aarch64-linux-gnu"

        true ->
          fail(
            "unsupported-target",
            "no reviewed bundle for this operating system or BEAM architecture"
          )
      end

    identity =
      if linux? do
        catalog =
          File.read!(Path.expand("../native/linux-bundles.json", __DIR__)) |> JSON.decode!()

        catalog[host_target] ||
          fail(
            "unsupported-target",
            "no reviewed #{host_target} bundle is pinned in this source package"
          )
      else
        File.read!(Path.expand("../native/local-bundle.json", __DIR__)) |> JSON.decode!()
      end

    Enum.each(identity["native_sources"], fn {name, expected} ->
      unless sha(File.read!(Path.expand("../native/" <> name, __DIR__))) == expected,
        do:
          fail(
            "incompatible-engine",
            "native interface source #{name} changed; rebuild and review a matching bundle identity"
          )
    end)

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

    supported = if linux?, do: ["x86_64-linux-gnu", "aarch64-linux-gnu"], else: ["aarch64-macos"]

    unless manifest["target"] in supported,
      do: fail("unsupported-target", "the artifact does not match this operating system")

    unless manifest["target"] == host_target and
             (linux? or String.starts_with?(architecture, "aarch64")),
           do: fail("wrong-architecture", "use a bundle matching the BEAM architecture")

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
             "-Dtarget=#{identity["target"]}" in candidate["flags"] and
             "-Dcpu=baseline" in candidate["flags"],
           do:
             fail(
               "unsupported-target",
               "expected the reviewed explicit target and baseline CPU flags"
             )

    unless List.to_string(:erlang.system_info(:version)) == identity["erts"] and
             System.version() == identity["elixir"] and
             List.to_string(:erlang.system_info(:nif_version)) == identity["nif_api"],
           do:
             fail(
               "unsupported-target",
               "use Elixir #{identity["elixir"]}, ERTS #{identity["erts"]} and NIF API #{identity["nif_api"]}; other runtime gates remain open"
             )

    prefix = "lib/aphid-#{identity["package_version"]}/priv/lib/"

    closure =
      if linux?,
        do: ~w(Elixir.Aphid.Native.so Elixir.Aphid.Proof.so libaphid_bridge.so liblbug.so),
        else: ~w(Elixir.Aphid.Native.so Elixir.Aphid.Proof.so libaphid_bridge.dylib liblbug.dylib)

    native =
      Map.new(closure, fn name ->
        bytes =
          files[prefix <> name] ||
            fail("missing", "bundle lacks #{name}; obtain the complete 0.1.0-dev bundle")

        case {linux?, bytes} do
          {false, <<0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0, 0, 1, _::binary>>} ->
            :ok

          {false, <<0xCF, 0xFA, 0xED, 0xFE, _::binary>>} ->
            fail("wrong-architecture", "#{name} is not ARM64")

          {true, <<0x7F, "ELF", 2, 1, 1, _::binary-size(9), 3, 0, machine::little-16, _::binary>>} ->
            expected = if host_target == "x86_64-linux-gnu", do: 62, else: 183

            unless machine == expected,
              do: fail("wrong-architecture", "#{name} has the wrong ELF machine architecture")

          _ ->
            fail(
              "unloadable",
              "#{name} is not a native shared library for this target; obtain a valid bundle"
            )
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

    notice_path = Path.expand("../THIRD_PARTY_NOTICES.txt", __DIR__)

    supplemental =
      case File.read(notice_path) do
        {:ok, bytes} ->
          bytes

        _ ->
          fail(
            "missing",
            "source package lacks THIRD_PARTY_NOTICES.txt; obtain the complete source package"
          )
      end

    notice_name = "licenses/aphid-supplemental.txt"

    if Map.has_key?(files, notice_name),
      do: fail("corrupt", "archive collides with the source-package notice supplement")

    licenses =
      Map.filter(files, fn {name, _} -> String.starts_with?(name, "licenses/") end)
      |> Map.put(notice_name, supplemental)

    license_hashes = Map.new(licenses, fn {name, bytes} -> {name, sha(bytes)} end)

    receipt =
      JSON.encode!(%{
        archive_sha256: String.downcase(digest),
        files: hashes,
        licenses: license_hashes,
        identity: identity
      })

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

      installed_hashes =
        Map.merge(license_hashes, Map.new(hashes, fn {n, h} -> {"lib/" <> n, h} end))

      Enum.each(installed_hashes, fn {n, h} ->
        path = Path.join(destination, n)

        unless File.regular?(path),
          do: fail("missing", "installed #{n} is absent; use an empty MIX_BUILD_PATH")

        unless sha(File.read!(path)) == h,
          do: fail("corrupt", "installed #{n} changed; use an empty MIX_BUILD_PATH")
      end)
    else
      # Extract into memory first. Only fixed native names and validated license paths
      # are written into a fresh directory; archive BEAM files are never installed.
      File.mkdir_p!(Path.dirname(destination))
      staging = destination <> ".aphid-" <> Integer.to_string(System.unique_integer([:positive]))
      File.mkdir!(staging)
      File.mkdir!(Path.join(staging, "lib"))
      Enum.each(native, fn {n, b} -> File.write!(Path.join([staging, "lib", n]), b) end)

      Enum.each(licenses, fn {name, bytes} ->
        path = Path.join(staging, name)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, bytes)
      end)

      File.write!(Path.join(staging, "aphid-bundle.json"), receipt)
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
    reject_existing_bundle()
    System.delete_env("APHID_BUNDLE_RECEIPT")
    {:noop, []}
  end

  defp reject_existing_bundle do
    if File.exists?(Path.join([Mix.Project.app_path(), "priv", "aphid-bundle.json"])),
      do:
        fail(
          "selection",
          "this build contains a local bundle; keep its archive/checksum selection or use an empty source build path"
        )
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
