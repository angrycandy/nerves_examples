defmodule UiWeb.SensorsLive do
  use UiWeb, :live_view
  require Logger
  require Math

  @impl true
  def mount(_params, _session, socket) do
    socket = socket
    |> start_scan()
    |> assign(:page_title, "Sensors")
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <section>
      <h2>Sensors</h2>
      <%= for {_, line} <- @val do %>
        <%= line %><br>
      <% end %>
      <%= if @scanning do %>
        Scanning...
      <% else %>
        <br>
        <button phx-click="scan">scan</button>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_event("scan", _, socket) do
    {:noreply, start_scan(socket)}
  end

  @impl true
  def handle_info("cancel", socket) do
    {:noreply, stop_scan(socket)}
  end

  @impl true
  def terminate(_reason, socket) do
    stop_scan(socket)
  end

  @impl true
  def handle_cast({addr, device}, socket) do
    if socket.assigns.scanning do
      {:noreply, add_device(addr, device, socket)}
    else
      {:noreply, socket}
    end
  end

  defp add_device(addr, device, socket) do
    dev = print(device)
    unless String.length(dev) == 0 do
      val = Map.put(socket.assigns.val, addr, dev)
      scanning = Enum.count(val) < 2
      Logger.info("#{__MODULE__} #{scanning} #{inspect(val)}")
      if scanning do
	assign(socket, :val, val)
      else
	socket
	|> assign(:val, val)
	|> stop_scan()
      end
    else
      socket
    end
  end

  # Limit the scan time to minimize battery drain on sensors that
  # send extra reports during active scan.
  @enable_time 12_000

  # If there are simultaneous users this should be its own Genserver,
  # but for a few users it's good enough.
  defp start_scan(socket) do
    if not Map.get(socket.assigns, :scanning, false) do
      pid = Process.whereis(BlueHeronScan)
      if pid do
	me = self()
	hook = fn arg -> GenServer.cast(me, arg) end
	GenServer.call(pid, {:device_update_hook, hook})
	GenServer.call(pid, :scan_enable)
	timer_me = Process.send_after(me, "cancel", @enable_time)
	timer_ble = Process.send_after(pid, :scan_disable, @enable_time)
	Logger.info("#{__MODULE__} #{inspect(me)} init BlueHeronScan")
	socket
	|> assign(:timers, [timer_ble, timer_me])
	|> assign(:val, %{})
	|> assign(:scanning, true)
      else
	Logger.info("#{__MODULE__} #{inspect(self())} no BlueHeronScan")
	socket
	|> assign(:val, %{0 => "Bluetooth scanner not found."})
	|> assign(:scanning, false)
      end
    else
      socket
    end
  end

  defp stop_scan(socket) do
    Logger.info("#{__MODULE__} stop scan")
    if socket.assigns.scanning do
      send(BlueHeronScan, :scan_disable)
      for timer_ref <- socket.assigns.timers do
	Process.cancel_timer(timer_ref, async: true, info: false)
      end
      assign(socket, :scanning, false)
    else
      socket
    end
  end

  defp print(device) do
    Enum.reduce(device, [], fn {k, v}, acc ->
      case print_device(k, v) do
	nil -> acc
	s -> [s <> " · " <> rename(Map.get(device, :name, "")) | acc]
      end
    end)
    |> Enum.join(" ")
  end

  # https://github.com/Home-Is-Where-You-Hang-Your-Hack/sensor.goveetemp_bt_hci
  # custom_components/govee_ble_hci/govee_advertisement.py
  # GVH5102 https://fccid.io/2AQA6-H5102 Thermo-Hygrometer
  defp print_device(0x0001, <<_::16, temhum::24, bat::8>>) do
    tem_c = temhum/10000
    rh = rem(temhum, 1000)/10
    summary(tem_c, rh, bat)
  end

  # https://github.com/wcbonner/GoveeBTTempLogger
  # goveebttemplogger.cpp
  # bool Govee_Temp::ReadMSG(const uint8_t * const data)
  # Govee_H5074 https://fccid.io/2AQA6-H5074 Thermo-Hygrometer
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

  defp rename(name) do
    nmap = %{
      "GVH5102_EED5" => "inside",
      "Govee_H5074_F092" => "outside"
    }
    Map.get(nmap, name, name)
  end

  defp summary(tem_c, rh, bat) do
    dew_c = dewpoint(tem_c, rh)
    dew_f = Float.round(c_to_f(dew_c), 1)
    tem_f = Float.round(c_to_f(tem_c), 1)
    "Temp #{tem_f}˚F Dew Pt #{dew_f}˚F 🔋#{bat}%"
  end

  # https://www.kgun9.com/weather/the-difference-between-dew-point-and-humidity
  # https://bmcnoldy.rsmas.miami.edu/Humidity.html
  # t˚C rh %
  defp dewpoint(t, rh) do
    243.04*(Math.log(rh/100)+((17.625*t)/(243.04+t))) /
    (17.625-Math.log(rh/100)-((17.625*t)/(243.04+t)))
  end

  defp c_to_f(c) do
    (c * 9/5) + 32
  end

end
