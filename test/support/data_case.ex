defmodule LittleGrape.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LittleGrape.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias LittleGrape.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import LittleGrape.DataCase
    end
  end

  setup tags do
    LittleGrape.DataCase.setup_sandbox(tags)
    LittleGrape.DataCase.setup_upload_cleanup()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(LittleGrape.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Sets up cleanup for uploaded files created during tests.
  Takes a snapshot of existing files before the test and removes any new files after.
  """
  def setup_upload_cleanup do
    uploads_dir =
      Path.join([:code.priv_dir(:little_grape), "static", "uploads", "profile_pictures"])

    existing_files =
      if File.exists?(uploads_dir) do
        File.ls!(uploads_dir) |> MapSet.new()
      else
        MapSet.new()
      end

    on_exit(fn ->
      if File.exists?(uploads_dir) do
        current_files = File.ls!(uploads_dir) |> MapSet.new()
        new_files = MapSet.difference(current_files, existing_files)

        Enum.each(new_files, fn file ->
          File.rm(Path.join(uploads_dir, file))
        end)
      end
    end)
  end

  @doc """
  Runs `fun` and returns `{result, query_count}` where `query_count` is the
  number of Ecto queries executed by (or on behalf of) the calling process,
  including preload queries Ecto runs concurrently in `Task` processes
  (attributed via the `$callers` chain).

  Safe under `async: true`: events from other test processes are filtered out.

      {result, count} = count_queries(fn -> Matches.list_matches_with_details(user) end)
      assert count == 8

  """
  def count_queries(fun) do
    ref = make_ref()
    test_pid = self()
    handler_id = {__MODULE__, :count_queries, ref}

    :telemetry.attach(
      handler_id,
      [:little_grape, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if test_pid == self() or test_pid in Process.get(:"$callers", []) do
          send(test_pid, {:query_counted, ref})
        end
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain_query_counts(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_query_counts(ref, count) do
    receive do
      {:query_counted, ^ref} -> drain_query_counts(ref, count + 1)
    after
      0 -> count
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
