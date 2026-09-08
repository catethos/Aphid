records = for path <- Path.wildcard("/private/tmp/aphid-small-review-1/beams/*/*.beam") do
  {:ok, {module, chunks}} = :beam_lib.chunks(String.to_charlist(path), [:atoms, :imports])
  atoms = chunks[:atoms] |> Enum.map(fn {_, atom} -> Atom.to_string(atom) end)
  matches = Enum.filter(atoms, fn atom -> String.contains?(String.downcase(atom), ["pegasus", "nimbleparsec", "nimble_parsec", "zig.parser", "zig_parser"]) end)
  %{file: path, module: Atom.to_string(module), parser_atoms: matches,
    imported_modules: chunks[:imports] |> Enum.map(fn {mod, _, _} -> Atom.to_string(mod) end) |> Enum.uniq() |> Enum.sort()}
end
IO.puts(JSON.encode!(records))
