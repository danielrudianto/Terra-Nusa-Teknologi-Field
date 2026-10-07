package id.co.alphakonstruksi.jam_monoton;

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
 * Jam monoton untuk deteksi "jam HP diedit".
 *
 * elapsedRealtime() berjalan sejak HP menyala, termasuk saat tidur, dan
 * TIDAK berubah bila jam di Pengaturan digeser. BOOT_COUNT membedakan
 * "masih nyala yang sama" dari "sudah dinyalakan ulang" — tanpa itu, jam
 * monoton setelah restart dibaca seolah lanjutan yang lama.
 *
 * Ditulis dalam Java, bukan Kotlin: plugin Java tidak bergantung pada
 * plugin Gradle Kotlin, yang cara pemasangannya berubah di AGP 9. Satu
 * berkas sekecil ini tidak sepadan dengan risiko gagal build itu.
 */
public class JamMonotonPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel saluran;
    private Context konteks;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        konteks = binding.getApplicationContext();
        saluran = new MethodChannel(binding.getBinaryMessenger(), "id.co.alphakonstruksi/jam_monoton");
        saluran.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (saluran != null) saluran.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"ambil".equals(call.method)) {
            result.notImplemented();
            return;
        }
        Integer boot;
        try {
            boot = Settings.Global.getInt(konteks.getContentResolver(), Settings.Global.BOOT_COUNT);
        } catch (Exception e) {
            boot = null;
        }
        Map<String, Object> hasil = new HashMap<>();
        hasil.put("elapsedMs", SystemClock.elapsedRealtime());
        hasil.put("bootCount", boot);
        result.success(hasil);
    }
}
