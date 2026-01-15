defmodule LittleGrape.Repo.Migrations.AddProfilePictureToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :profile_picture, :string
    end
  end
end
