{:ok, db} = Aphid.start_link(path: :memory)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Person(id INT64, PRIMARY KEY(id))")
{:ok, _} = Aphid.query(db, "CREATE REL TABLE Knows(FROM Person TO Person)")
{:ok, _} = Aphid.query(db, "CREATE (:Person {id: 1}), (:Person {id: 2})")

{:ok, _} =
  Aphid.query(db, "MATCH (a:Person {id: 1}), (b:Person {id: 2}) CREATE (a)-[:Knows]->(b)")

# ALGO is registered at startup; no INSTALL or LOAD is needed.
{:ok, _} = Aphid.query(db, "CALL PROJECT_GRAPH('social', ['Person'], ['Knows'])")

{:ok, %Aphid.Result{rows: [[2, higher], [1, lower]]}} =
  Aphid.query(db, "CALL PAGE_RANK('social') RETURN node.id, rank ORDER BY rank DESC, node.id")

true = higher > lower
{:ok, _} = Aphid.query(db, "CALL DROP_PROJECTED_GRAPH('social')")
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid graph algorithm example passed")
