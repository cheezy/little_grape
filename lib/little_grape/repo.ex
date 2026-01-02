defmodule LittleGrape.Repo do
  use Ecto.Repo,
    otp_app: :little_grape,
    adapter: Ecto.Adapters.Postgres
end
