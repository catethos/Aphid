defmodule Aphid.Native do
  @moduledoc false
  use Zig,
    otp_app: :aphid,
    zig_code_path: "../../native/aphid_nif.zig",
    callbacks: [on_load: :load, on_upgrade: :upgrade],
    nifs: [
      open: [concurrency: :dirty_cpu],
      open_configured: [concurrency: :dirty_cpu],
      submit: [concurrency: :dirty_cpu],
      submit_lease: [concurrency: :dirty_cpu],
      lease_acquire: [],
      lease_release: [],
      transaction_control: [],
      collect: [concurrency: :dirty_cpu],
      fetch: [concurrency: :dirty_cpu],
      close: [],
      closed: [],
      state: [],
      cancel: [],
      finish: [],
      operation_error: [],
      transferring: [],
      stats: []
    ],
    c: [
      headers: [bridge: "../../native/bridge.h"],
      link_lib: ["../../_build/native/bridge/libaphid_bridge.dylib"],
      rpaths: ["../../_build/native/bridge", "../../_build/native/ladybug/src"]
    ]

  if build = System.get_env("APHID_NATIVE_BUILD_ROOT") do
    suffix = if :os.type() == {:unix, :linux}, do: ".so", else: ".dylib"
    unless Path.type(build) == :absolute,
      do:
        raise(
          ArgumentError,
          "APHID_NATIVE_BUILD_ROOT must be an absolute native output directory"
        )

    @zigler_opts Keyword.update!(@zigler_opts, :c, fn options ->
                   Keyword.merge(options,
                     link_lib: [Path.join(build, "bridge/libaphid_bridge" <> suffix)],
                     rpaths: [Path.join(build, "bridge"), Path.join(build, "ladybug/src")]
                   )
                 end)
  end

  if path = System.get_env("APHID_NATIVE_PRECOMPILED") do
    @zigler_opts Keyword.put(@zigler_opts, :precompiled, path)
  end

  @before_compile Aphid.BundleLoader
  def submit(database, session, query), do: submit(database, session, query, %{})
end
