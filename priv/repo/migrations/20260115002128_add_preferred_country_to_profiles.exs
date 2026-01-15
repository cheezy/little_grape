defmodule LittleGrape.Repo.Migrations.AddPreferredCountryToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :preferred_country, :string, size: 10
      remove :preferred_distance_km
    end
  end
end
