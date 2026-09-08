defmodule Aphid.ProofTest do
  use ExUnit.Case, async: false

  test "C++ ABI and widening arithmetic" do
    assert Aphid.Proof.abi_version() == 1
    assert Aphid.Proof.add(2_147_483_647, 2_147_483_647) == 4_294_967_294
    assert_raise ArgumentError, fn -> Aphid.Proof.add(2_147_483_648, 0) end
  end

  test "resource dies with its last owning process" do
    baseline = Aphid.Proof.live_tokens()
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        token = Aphid.Proof.token()
        send(parent, {:ready, Aphid.Proof.token_value(token)})

        receive do
          :stop -> Aphid.Proof.token_value(token)
        end
      end)

    assert_receive {:ready, 1}
    assert Aphid.Proof.live_tokens() == baseline + 1
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    await_cleanup(baseline, 100)
  end

  defp await_cleanup(expected, remaining) do
    if Aphid.Proof.live_tokens() != expected and remaining > 0 do
      Process.sleep(10)
      await_cleanup(expected, remaining - 1)
    else
      assert Aphid.Proof.live_tokens() == expected
    end
  end
end
