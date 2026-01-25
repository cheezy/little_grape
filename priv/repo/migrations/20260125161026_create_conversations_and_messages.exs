defmodule LittleGrape.Repo.Migrations.CreateConversationsAndMessages do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :match_id, references(:matches, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversations, [:match_id])

    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:users, on_delete: :delete_all), null: false
      add :content, :string, size: 2000, null: false
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:messages, [:conversation_id, :inserted_at])
    create index(:messages, [:conversation_id, :sender_id, :read_at])
  end
end
