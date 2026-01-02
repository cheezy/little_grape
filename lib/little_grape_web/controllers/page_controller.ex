defmodule LittleGrapeWeb.PageController do
  use LittleGrapeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
