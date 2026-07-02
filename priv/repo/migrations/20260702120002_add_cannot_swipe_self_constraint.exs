defmodule LittleGrape.Repo.Migrations.AddCannotSwipeSelfConstraint do
  use Ecto.Migration

  def change do
    create constraint(:swipes, :cannot_swipe_self, check: "user_id != target_user_id")
  end
end
