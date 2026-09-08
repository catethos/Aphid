# Hex 2.5.1: publish the exact qualified tarball using its normal auth/OTP flow.
# Matches lib/mix/tasks/hex.publish.ex's Hex.API.Release.publish/5 call.
Mix.start()
Hex.start()
[path, expected] = System.argv()
true = Regex.match?(~r/\A[0-9a-f]{64}\z/, expected)
tarball = File.read!(path)
^expected = :crypto.hash(:sha256, tarball) |> Base.encode16(case: :lower)

case Hex.API.Release.get(nil, "aphid", "0.1.2-dev") do
  {:ok, {404, _, _}} -> :ok
  {:ok, {200, _, _}} -> raise "Version already exists; inspect registry before retrying."
  other ->
    Hex.Utils.print_error_result(other)
    System.halt(1)
end

case Hex.API.Release.publish(nil, tarball, [], fn _ -> :ok end, false) do
  {:ok, {code, _, body}} when code in 200..299 ->
    IO.puts("Published #{body["html_url"] || body["url"]}; SHA256 #{expected}")
  other ->
    Hex.Utils.print_error_result(other)
    System.halt(1)
end
