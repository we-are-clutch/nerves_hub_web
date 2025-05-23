defmodule NervesHub.Extensions.Health do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Helpers.Logging

  require Logger

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of fundamental device metrics, metadata, alarms and more.
    Also supports custom metrics. Alarms require an alarm handler to be set.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(socket) do
    extension_config = Application.get_env(:nerves_hub, :extension_config, [])

    health_interval =
      case get_in(extension_config, [:health, :interval_minutes]) do
        i when is_integer(i) and i > 0 -> i
        _ -> 60
      end

    send(self(), {__MODULE__, :check})

    timer =
      health_interval
      |> :timer.minutes()
      |> :timer.send_interval({__MODULE__, :check})

    socket =
      socket
      |> Phoenix.Socket.assign(:health_interval, health_interval)
      |> Phoenix.Socket.assign(:health_timer, timer)

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def detach(socket) do
    _ = if socket.assigns[:health_timer], do: :timer.cancel(socket.assigns.health_timer)
    {:noreply, Phoenix.Socket.assign(socket, :health_timer, nil)}
  end

  @impl NervesHub.Extensions
  def handle_in("report", %{"value" => device_report}, socket) do
    # Get metrics from health report to store in metrics table and calculate status
    metrics = device_report["metrics"] || %{}

    # Get device status together with reasons, if any.
    {status, reasons} =
      case HealthStatus.calculate_metrics_status(metrics) do
        {status, reasons} -> {status, reasons}
        status -> {status, nil}
      end

    device_health = %{
      "device_id" => socket.assigns.device.id,
      "data" => device_report,
      "status" => status,
      "status_reasons" => reasons
    }

    with {:health_report, {:ok, _}} <-
           {:health_report, Devices.save_device_health(device_health)},
         {:metrics_report, {:ok, _}} <-
           {:metrics_report, Metrics.save_metrics(socket.assigns.device.id, metrics)} do
      :ok = device_internal_broadcast!(socket.assigns.device, "health_check_report", %{})
    else
      {:health_report, {:error, err}} ->
        Logger.warning("Failed to save health check data: #{inspect(err)}")

        Logging.log_to_sentry(
          socket.assigns.device,
          "[DeviceChannel] Failed to save health check data."
        )

      {:metrics_report, :error} ->
        Logger.warning("Failed to save metrics report")

        Logging.log_to_sentry(
          socket.assigns.device,
          "[DeviceChannel] Failed to save metrics report."
        )
    end

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(:check, socket) do
    Phoenix.Channel.push(socket, "health:check", %{})
    {:noreply, socket}
  end

  def request_health_check(device) do
    :ok = device_internal_broadcast!(device, "health:check", %{})
  end

  defp device_internal_broadcast!(device, event, payload) do
    topic = "device:#{device.id}:extensions"

    Phoenix.Channel.Server.broadcast_from!(NervesHub.PubSub, self(), topic, event, payload)
  end
end
