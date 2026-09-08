# Publish the already-qualified tarball through the same Hex API/auth flow as
# mix hex.publish, without rebuilding its platform-dependent metadata order.
Mix.start()
Hex.start()
path = "/private/tmp/aphid-011-publication/aphid-0.1.1-dev-reviewed.tar"
expected = "9faa9af3eb1c826446b0bf9473e94632e4fbb9fcb6bfc9d85bae1a90862f2448"
tarball = File.read!(path)
^expected = :crypto.hash(:sha256, tarball) |> Base.encode16(case: :lower)

case Hex.API.Release.get(nil, "aphid", "0.1.1-dev") do
  {:ok, {404, _, _}} -> :ok
  {:ok, {200, _, _}} -> raise "Version already exists; inspect registry before retrying."
  other ->
    Hex.Utils.print_error_result(other)
    System.halt(1)
end

auth = Mix.Tasks.Hex.auth_info(:write)
case Hex.API.Release.publish(nil, tarball, auth, fn _ -> :ok end, false) do
  {:ok, {code, _, body}} when code in 200..299 ->
    IO.puts("Published #{body["html_url"] || body["url"]}; SHA256 #{expected}")
  other ->
    Hex.Utils.print_error_result(other)
    System.halt(1)
end
