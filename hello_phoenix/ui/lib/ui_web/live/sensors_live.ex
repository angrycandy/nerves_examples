defmodule UiWeb.SensorsLive do
  use UiWeb, :live_view

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(:page_title, "Sensors")
    |> assign(:val, 0)
    {:ok, socket}
  end

  def handle_event("inc", _, socket) do
    {:noreply, update(socket, :val, &(&1 + 1))}
  end

  def handle_event("dec", _, socket) do
    {:noreply, update(socket, :val, &(&1 - 1))}
  end

  def render(assigns) do
    ~L"""
    <div>
      <h1>The count is: <%= @val %></h1>
      <button phx-click="dec">-</button>
      <button phx-click="inc">+</button>
    </div>
    """
  end
end
