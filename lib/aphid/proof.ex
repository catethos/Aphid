defmodule Aphid.Proof do
  @moduledoc false
  use Zig,
    otp_app: :aphid,
    zig_code_path: "../../native/proof.zig",
    resources: [:Token],
    c: [
      headers: [bridge: "../../native/proof.h"],
      src: [{"../../native/proof.cpp", ["-std=c++17"]}]
    ]

  if path = System.get_env("APHID_PROOF_PRECOMPILED") do
    @zigler_opts Keyword.put(@zigler_opts, :precompiled, path)
  end

  if System.get_env("APHID_BUNDLE_RECEIPT") do
    @before_compile Aphid.BundleLoader
  end
end
