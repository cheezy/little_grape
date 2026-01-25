defmodule LittleGrape.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :user_a_id, references(:users, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, on_delete: :delete_all), null: false
      add :matched_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:matches, [:user_a_id, :user_b_id])
    create index(:matches, [:user_b_id])

    # Constraint to ensure user_a_id < user_b_id (prevents duplicate pairs)
    create constraint(:matches, :user_a_less_than_user_b, check: "user_a_id < user_b_id")
  end
end
