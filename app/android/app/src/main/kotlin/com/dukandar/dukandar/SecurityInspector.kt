package com.dukandar.dukandar

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.security.MessageDigest

/**
 * On-device tamper checks. Everything here is best-effort heuristics; the
 * Dart side decides what combination locks the app.
 */
object SecurityInspector {

    fun inspect(context: Context): Map<String, Any?> {
        val rootHits = rootIndicators()
        val hookHits = hookingIndicators(context)
        val details = HashMap<String, Any?>()
        if (rootHits.isNotEmpty()) details["root"] = rootHits.joinToString(",")
        if (hookHits.isNotEmpty()) details["hooking"] = hookHits.joinToString(",")
        details["emulator"] = emulatorIndicators().joinToString(",")

        return mapOf(
            "isRooted" to rootHits.isNotEmpty(),
            "isDebuggerAttached" to (Debug.isDebuggerConnected() || Debug.waitingForDebugger()),
            "hookingDetected" to hookHits.isNotEmpty(),
            "isEmulator" to emulatorIndicators().isNotEmpty(),
            "signatureSha256" to signatureSha256(context),
            "isDebugBuild" to BuildConfig.DEBUG,
            "details" to details,
        )
    }

    // ------------------------------------------------------------------
    // Root
    // ------------------------------------------------------------------

    private val suPaths = listOf(
        "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
        "/system/sd/xbin/su", "/system/bin/failsafe/su", "/data/local/su",
        "/data/local/bin/su", "/data/local/xbin/su", "/system/app/Superuser.apk",
        "/system/app/SuperSU.apk", "/system/xbin/daemonsu", "/system/etc/init.d/99SuperSUDaemon",
        "/system/bin/.ext/.su", "/system/usr/we-need-root/su-backup", "/system/xbin/mu",
        "/vendor/bin/su", "/odm/bin/su", "/product/bin/su", "/apex/com.android.runtime/bin/su",
        "/sbin/magisk", "/sbin/.magisk", "/data/adb/magisk", "/data/adb/magisk.img",
        "/data/adb/magisk.db", "/data/adb/modules", "/cache/.disable_magisk",
        "/dev/.magisk.unblock", "/cache/magisk.log", "/data/adb/ksu", "/data/adb/ksud",
        "/system/xbin/busybox", "/system/bin/busybox", "/sbin/busybox", "/data/local/busybox",
    )

    private val rootPackages = listOf(
        "com.topjohnwu.magisk", "io.github.huskydg.magisk", "eu.chainfire.supersu",
        "com.koushikdutta.superuser", "com.noshufou.android.su", "com.noshufou.android.su.elite",
        "com.thirdparty.superuser", "com.yellowes.su", "com.kingroot.kinguser", "com.kingo.root",
        "com.smedialink.oneclickroot", "com.zhiqupk.root.global", "com.alephzain.framaroot",
        "me.weishu.kernelsu", "com.devadvance.rootcloak", "com.devadvance.rootcloakplus",
        "de.robv.android.xposed.installer", "com.saurik.substrate", "com.zachspong.temprootremovejb",
        "com.amphoras.hidemyroot", "com.amphoras.hidemyrootadfree", "com.formyhm.hiderootPremium",
        "com.formyhm.hideroot",
    )

    private fun rootIndicators(): List<String> {
        val hits = ArrayList<String>()
        // Soft indicators (build props) are normal on emulators / AOSP images,
        // so they only count on real hardware.
        val emulator = emulatorIndicators().isNotEmpty()
        if (!emulator && Build.TAGS?.contains("test-keys") == true) hits.add("test-keys")
        for (p in suPaths) {
            try {
                if (File(p).exists()) hits.add(p)
            } catch (_: Throwable) {
            }
        }
        // `which su` style PATH scan.
        try {
            System.getenv("PATH")?.split(":")?.forEach { dir ->
                if (File(dir, "su").exists()) hits.add("$dir/su")
            }
        } catch (_: Throwable) {
        }
        // Dangerous system properties.
        if (!emulator && getProp("ro.debuggable") == "1") hits.add("ro.debuggable")
        if (!emulator && getProp("ro.secure") == "0") hits.add("ro.secure=0")
        // Writable system partitions.
        try {
            BufferedReader(FileReader("/proc/mounts")).use { r ->
                r.lineSequence().forEach { line ->
                    val parts = line.split(" ")
                    if (parts.size >= 4) {
                        val mount = parts[1]
                        val opts = parts[3].split(",")
                        if ((mount == "/system" || mount == "/system/bin" || mount == "/vendor" || mount == "/sbin") &&
                            opts.contains("rw")
                        ) hits.add("rw:$mount")
                    }
                }
            }
        } catch (_: Throwable) {
        }
        // Try executing su (will fail on non-rooted phones quickly).
        try {
            val proc = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            val out = BufferedReader(proc.inputStream.reader()).readLine()
            proc.destroy()
            if (!out.isNullOrBlank()) hits.add("which-su")
        } catch (_: Throwable) {
        }
        return hits.distinct()
    }

    private fun getProp(name: String): String? = try {
        val p = Runtime.getRuntime().exec(arrayOf("getprop", name))
        val v = BufferedReader(p.inputStream.reader()).readLine()
        p.destroy()
        v?.trim()
    } catch (_: Throwable) {
        null
    }

    private fun hasPackage(context: Context, pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: Throwable) {
        false
    }

    // ------------------------------------------------------------------
    // Hooking frameworks (Frida / Xposed / Substrate)
    // ------------------------------------------------------------------

    private val hookClassNames = listOf(
        "de.robv.android.xposed.XposedBridge",
        "de.robv.android.xposed.XposedHelpers",
        "de.robv.android.xposed.XC_MethodHook",
        "com.saurik.substrate.MS\$2",
        "com.saurik.substrate.MS",
        "org.lsposed.lspd.core.Main",
        "io.github.lsposed.lspd.core.Main",
        "com.elderdrivers.riru.edxp.core.Main",
    )

    private val hookLibHints = listOf(
        "frida", "gadget", "xposed", "lsposed", "edxposed", "substrate", "riru",
        "zygisk", "libdobby", "libsandhook", "libwhale", "libepic", "libxhook",
    )

    private val hookFiles = listOf(
        "/data/local/tmp/frida-server", "/data/local/tmp/re.frida.server",
        "/data/local/tmp/frida-agent.so", "/data/local/tmp/frida-gadget.so",
        "/system/lib/libxposed_art.so", "/system/lib64/libxposed_art.so",
        "/system/framework/XposedBridge.jar", "/system/lib/libsubstrate.so",
        "/system/lib/libsubstrate-dvm.so", "/data/adb/lspd", "/data/adb/modules/riru_lsposed",
        "/data/adb/modules/zygisk_lsposed", "/data/adb/riru", "/data/adb/riru_lsposed",
    )

    private fun hookingIndicators(context: Context): List<String> {
        val hits = ArrayList<String>()
        for (c in hookClassNames) {
            try {
                Class.forName(c)
                hits.add("class:$c")
            } catch (_: Throwable) {
            }
        }
        for (f in hookFiles) {
            try {
                if (File(f).exists()) hits.add(f)
            } catch (_: Throwable) {
            }
        }
        for (p in rootPackages) {
            if ((p.contains("xposed") || p.contains("substrate")) && hasPackage(context, p)) hits.add("pkg:$p")
        }
        // Scan loaded libraries.
        try {
            BufferedReader(FileReader("/proc/self/maps")).use { r ->
                r.lineSequence().forEach { line ->
                    val lower = line.lowercase()
                    for (h in hookLibHints) {
                        if (lower.contains(h)) {
                            hits.add("maps:$h")
                            break
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        }
        // Frida default port listener.
        try {
            BufferedReader(FileReader("/proc/net/tcp")).use { r ->
                r.lineSequence().drop(1).forEach { line ->
                    val cols = line.trim().split(Regex("\\s+"))
                    if (cols.size > 3) {
                        val local = cols[1]
                        val port = local.substringAfter(":", "")
                        // 69A2 = 27042 (frida), 69A3 = 27043
                        if ((port.equals("69A2", true) || port.equals("69A3", true)) && cols[3] == "0A") {
                            hits.add("port:27042")
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        }
        // Stack trace inspection for Xposed.
        try {
            throw Exception("probe")
        } catch (e: Exception) {
            for (el in e.stackTrace) {
                val cn = el.className
                if (cn.contains("de.robv.android.xposed") || cn.contains("com.saurik.substrate") ||
                    cn.contains("lsposed")
                ) {
                    hits.add("stack:$cn")
                    break
                }
            }
        }
        return hits.distinct()
    }

    // ------------------------------------------------------------------
    // Emulator heuristics (informational – never locks on its own)
    // ------------------------------------------------------------------

    private fun emulatorIndicators(): List<String> {
        val hits = ArrayList<String>()
        val fp = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hw = Build.HARDWARE.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val manuf = Build.MANUFACTURER.lowercase()

        if (fp.startsWith("generic") || fp.startsWith("unknown") || fp.contains("emulator") ||
            fp.contains("sdk_gphone") || fp.contains("vbox") || fp.contains("test-keys")
        ) hits.add("fingerprint")
        if (model.contains("google_sdk") || model.contains("emulator") || model.contains("android sdk built for") ||
            model.contains("sdk_gphone") || model.contains("droid4x") || model.contains("vbox")
        ) hits.add("model")
        if (product.contains("sdk") || product.contains("google_sdk") || product.contains("sdk_gphone") ||
            product.contains("vbox86p") || product.contains("emulator") || product.contains("simulator") ||
            product.contains("nox") || product.contains("genymotion")
        ) hits.add("product")
        if (hw.contains("goldfish") || hw.contains("ranchu") || hw.contains("vbox86") || hw.contains("nox") ||
            hw.contains("ttvm_x86")
        ) hits.add("hardware")
        if (manuf.contains("genymotion") || manuf.contains("unknown")) hits.add("manufacturer")
        if (brand.startsWith("generic") && device.startsWith("generic")) hits.add("brand/device")
        if (Build.BOARD.lowercase().contains("nox")) hits.add("board")
        if (getProp("ro.kernel.qemu") == "1") hits.add("qemu")
        for (f in listOf("/dev/socket/qemud", "/dev/qemu_pipe", "/system/lib/libc_malloc_debug_qemu.so",
            "/sys/qemu_trace", "/system/bin/qemu-props", "/dev/socket/genyd", "/dev/socket/baseband_genyd")
        ) {
            try {
                if (File(f).exists()) hits.add(f)
            } catch (_: Throwable) {
            }
        }
        return hits
    }

    // ------------------------------------------------------------------
    // Signing certificate
    // ------------------------------------------------------------------

    @Suppress("DEPRECATION")
    fun signatureSha256(context: Context): String {
        return try {
            val pm = context.packageManager
            val pkg = context.packageName
            val sigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
                val si = info.signingInfo
                if (si == null) emptyArray()
                else if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
            } else {
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures ?: emptyArray()
            }
            val first = sigs?.firstOrNull() ?: return ""
            val md = MessageDigest.getInstance("SHA-256")
            md.digest(first.toByteArray()).joinToString("") { "%02x".format(it) }
        } catch (_: Throwable) {
            ""
        }
    }
}
