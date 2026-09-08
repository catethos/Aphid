defmodule Aphid.FeatureProof do
  @moduledoc false
  use Zig,
    otp_app: :aphid,
    zig_code_path: "../native/tests/features.zig",
    nifs: [check: [concurrency: :dirty_cpu]],
    c: [
      headers: [features: "../native/tests/features.h"],
      link_lib: ["../_build/native/tests/libaphid_feature_bridge.dylib"],
      rpaths: ["../_build/native/tests", "../_build/native/ladybug/src"]
    ]
end
