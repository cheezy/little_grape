defmodule LittleGrape.Repo.Migrations.AddOtherLanguagesField do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :other_languages, :string, size: 255
    end
  end
end
