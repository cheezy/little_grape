defmodule LittleGrape.Repo.Migrations.CreateSwipes do
  use Ecto.Migration

  def change do
    create table(:swipes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :target_user_id, references(:users, on_delete: :delete_all), null: false
      add :action, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:swipes, [:user_id, :target_user_id])
    create index(:swipes, [:target_user_id, :action])
  end
end
