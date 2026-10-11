package id.co.alphakonstruksi.monotonic_clock;

import android.content.Context;
import android.os.SystemClock;
import android.provider.Settings;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Monotonic clock used to detect "phone clock was edited".
 *
 * elapsedRealtime() counts from boot, including deep sleep, and does NOT move
 * when the wall clock is changed in Settings. BOOT_COUNT tells "still the same
 * boot" apart from "rebooted since" — without it, a monotonic reading taken
 * after a reboot would be mistaken for a continuation of the previous one.
 *
 * Written in Java, not Kotlin: a Java plugin does not depend on the Kotlin
 * Gradle plugin, whose setup changed in AGP 9. A file this small is not worth
 * that build risk.
 */
public class MonotonicClockPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "id.co.alphakonstruksi/monotonic_clock");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"read".equals(call.method)) {
            result.notImplemented();
            return;
        }
        Integer boot;
        try {
            boot = Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT);
        } catch (Exception e) {
            boot = null;
        }
        Map<String, Object> reading = new HashMap<>();
        reading.put("elapsedMs", SystemClock.elapsedRealtime());
        reading.put("bootCount", boot);
        result.success(reading);
    }
}
