defmodule UiWeb.SensorsLive do
  use UiWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    init_ble()
    socket = socket
    |> assign(:page_title, "Sensors")
    |> assign(:val, %{})
    |> assign(:scanning, true)
    {:ok, socket}
  end

  @impl true
  def handle_event("scan", _, socket) do
    init_ble()
    socket = socket
    |> assign(:val, %{})
    |> assign(:scanning, true)
    {:noreply, socket}
  end

  @impl true
  def handle_info("cancel", socket) do
    socket = socket
    |> assign(:scanning, false)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <section>
      <h2>Inside · Out</h2>
      <%= for {_, line} <- @val do %>
        <%= line %><br>
      <% end %>
      <%= if @scanning do %>
        Scanning...
      <% else %>
        <button phx-click="scan">scan</button>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_cast({addr, dmap}, socket) do
    dev = device(dmap)
    socket =
    unless String.length(dev) == 0 do
      val = Map.put(socket.assigns.val, addr, dev)
      done = Enum.count(val) < 2
      Logger.info("#{__MODULE__} #{done} #{inspect(val)}")
      if done do
      end
      socket
      |> assign(:val, val)
      |> assign(:scanning, Enum.count(val) < 2)
    else
      socket
    end
    {:noreply, socket}
  end

  @enable_time 10000

  defp init_ble() do
    pid = Process.whereis(BlueHeronScan)
    if pid do
      me = self()
      hook = fn arg -> GenServer.cast(me, arg) end
      GenServer.call(pid, {:device_update_hook, hook})
      GenServer.call(pid, :scan_enable)
      Process.send_after(pid, :scan_disable, @enable_time)
      Process.send_after(self(), "cancel", @enable_time)
      Logger.info("#{__MODULE__} #{inspect(self())} init BlueHeronScan")
    else
      Logger.info("#{__MODULE__} #{inspect(self())} no BlueHeronScan")
    end
  end

  require Math

  defp device(dmap) do
    Enum.reduce(dmap, [], fn {k, v}, acc ->
      case print_device(k, v) do
	nil -> acc
	s -> [s <> " · " <> Map.get(dmap, :name, "") | acc]
      end
    end)
    |> Enum.join(" ")
  end

  # https://bmcnoldy.rsmas.miami.edu/Humidity.html
  # t˚C rh %
  defp dewpoint(t, rh) do
    243.04*(Math.log(rh/100)+((17.625*t)/(243.04+t))) /
    (17.625-Math.log(rh/100)-((17.625*t)/(243.04+t)))
  end

  defp c_to_f(c) do
    (c * 9/5) + 32
  end

  defp summary(tem_c, rh, bat) do
    dew_c = dewpoint(tem_c, rh)
    dew_f = Float.round(c_to_f(dew_c), 1)
    tem_f = Float.round(c_to_f(tem_c), 1)
    "Temp #{tem_f}˚F Dew Pt #{dew_f}˚F 🔋#{bat}%"
  end

  # https://github.com/Home-Is-Where-You-Hang-Your-Hack/sensor.goveetemp_bt_hci
  # custom_components/govee_ble_hci/govee_advertisement.py
  # GVH5102
  defp print_device(0x0001, <<_::16, temhum::24, bat::8>>) do
    tem_c = temhum/10000
    rh = rem(temhum, 1000)/10
    summary(tem_c, rh, bat)
  end

  # https://github.com/wcbonner/GoveeBTTempLogger
  # goveebttemplogger.cpp
  # bool Govee_Temp::ReadMSG(const uint8_t * const data)
  # Govee_H5074
  defp print_device(0xec88, <<_::8, tem::little-16, hum::little-16,
    bat::8, _::8>>
  ) do
    tem_c = tem/100
    rh = hum/100
    summary(tem_c, rh, bat)
  end

  defp print_device(_cid, _data) do
    nil
  end

end
