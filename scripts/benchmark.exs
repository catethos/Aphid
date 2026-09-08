[setup, cases] = System.argv()

{:ok, db} =
  Aphid.start_link(path: :memory, sessions: 1, threads: 2, buffer_pool_bytes: 67_108_864)

query = fn text, expected ->
  {:ok, %Aphid.Result{rows: rows}} = Aphid.query(db, text)
  if expected != nil, do: true = length(rows) == expected
end

setup |> File.stream!() |> Enum.each(&query.(String.trim_trailing(&1), nil))

for line <- File.stream!(cases) do
  [name, expected, text] = line |> String.trim_trailing() |> String.split("\t", parts: 3)
  expected = String.to_integer(expected)
  for _ <- 1..20, do: query.(text, expected)

  samples =
    for _ <- 1..100 do
      started = System.monotonic_time(:nanosecond)
      query.(text, expected)
      (System.monotonic_time(:nanosecond) - started) / 1000
    end

  IO.puts(
    JSON.encode!(%{
      implementation: "aphid",
      case: name,
      samples_us: samples,
      beam_memory_bytes: :erlang.memory(:total)
    })
  )
end

:ok = Aphid.close(db)
