defmodule LittleGrape.MatchesFixtures do
  @moduledoc """
  Schema-level test helpers for `LittleGrape.Matches.Match`.

  Deliberately inserts via `Match.changeset/2` + `Repo.insert/1` instead of
  `Matches.create_match/2`: the context function also creates a conversation,
  deduplicates, and broadcasts — schema/migration tests need a bare match row
  with no side effects.
  """

  import LittleGrape.AccountsFixtures, only: [user_fixture: 0]

  alias LittleGrape.Matches.Match
  alias LittleGrape.Repo

  def match_fixture, do: match_fixture(user_fixture(), user_fixture())

  def match_fixture(user_a, user_b) do
    {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

    {:ok, match} =
      %Match{}
      |> Match.changeset(%{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      })
      |> Repo.insert()

    match
  end
end
