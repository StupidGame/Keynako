package io.github.StupidGame.azookey_flutter.conversion

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.kazumaproject.zenz.ZenzEngine
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Owns model preparation, serialized inference, cancellation and result delivery. */
internal class AndroidZenzaiRuntime(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "KeynakoZenzai")
    }
    private val requestSequence = AtomicLong(0)

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var closed = false

    fun prepare(modelSize: String) {
        if (closed) return
        executor.execute {
            runCatching { ensureModel(modelSize) }
                .onSuccess { ready ->
                    if (ready) Log.i(LOG_TAG, "Prepared $modelSize model")
                    else Log.w(LOG_TAG, "Could not prepare $modelSize model")
                }
                .onFailure { error -> Log.e(LOG_TAG, "Failed to prepare $modelSize model", error) }
        }
    }

    fun rank(
        modelSize: String,
        reading: String,
        leftContext: String,
        rightContext: String,
        baseCandidates: List<String>,
        maxTokens: Int,
        callback: (List<String>) -> Unit,
    ) {
        if (closed) return
        val request = requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
        executor.execute {
            if (closed || request != requestSequence.get()) return@execute
            val startedAt = System.nanoTime()
            val result = runCatching {
                if (!ensureModel(modelSize)) return@runCatching emptyList()
                if (request != requestSequence.get()) return@runCatching emptyList()

                val generated = ZenzEngine.generateWithContextAndConditionsV32(
                    "",
                    "",
                    "",
                    "",
                    leftContext,
                    rightContext,
                    reading,
                    maxTokens,
                ).trim().takeIf { it.isPlausibleZenzaiCandidate(reading) }.orEmpty()
                if (request != requestSequence.get()) return@runCatching emptyList()

                val values = linkedSetOf<String>()
                if (generated.isNotEmpty()) values.add(generated)
                values.addAll(baseCandidates.filter { it.isNotBlank() })
                if (values.isEmpty()) return@runCatching emptyList()

                // Scoring every entry in the large dictionary makes inference lag behind typing.
                // Zenzai reranks the strongest entries and preserves the remaining dictionary order.
                val candidates = values.toList()
                val rerankedCandidates = candidates.take(MAX_RERANKED_CANDIDATES)
                val scores = ZenzEngine.scoreCandidatesV32(
                    null,
                    null,
                    null,
                    null,
                    leftContext,
                    rightContext,
                    reading,
                    rerankedCandidates.toTypedArray(),
                )
                rerankedCandidates.withIndex().sortedWith(
                    compareByDescending<IndexedValue<String>> { indexed ->
                        scores.getOrNull(indexed.index)
                            ?.takeIf { it.isFinite() }
                            ?: Float.NEGATIVE_INFINITY
                    }.thenBy { it.index },
                ).map { it.value } + candidates.drop(rerankedCandidates.size)
            }.getOrElse { error ->
                Log.e(LOG_TAG, "Candidate ranking failed", error)
                emptyList()
            }

            if (result.isEmpty() || closed || request != requestSequence.get()) {
                if (request == requestSequence.get()) Log.w(LOG_TAG, "Candidate ranking returned no result")
                return@execute
            }
            Log.i(
                LOG_TAG,
                "Ranked ${result.size} candidates with $modelSize in " +
                    "${(System.nanoTime() - startedAt) / 1_000_000} ms",
            )
            mainHandler.post {
                if (!closed && request == requestSequence.get()) callback(result)
            }
        }
    }

    fun cancel() {
        requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
    }

    fun close() {
        if (closed) return
        closed = true
        requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
        executor.execute {
            runCatching { ZenzEngine.closeModel() }
            loadedModelPath = null
        }
        executor.shutdown()
    }

    private fun ensureModel(modelSize: String): Boolean {
        if (closed) return false
        val model = ZenzaiModelManager(appContext).prepare(modelSize) ?: return false
        if (loadedModelPath != model.absolutePath) {
            if (loadedModelPath != null) ZenzEngine.closeModel()
            if (!ZenzEngine.initModel(model.absolutePath)) {
                loadedModelPath = null
                return false
            }
            loadedModelPath = model.absolutePath
        }
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        ZenzEngine.setRuntimeConfig(512, threads)
        return true
    }

    private companion object {
        const val LOG_TAG = "KeynakoZenzai"
        const val MAX_RERANKED_CANDIDATES = 16
    }
}

private fun String.isPlausibleZenzaiCandidate(reading: String): Boolean {
    if (isEmpty()) return false
    val maximumLength = maxOf(48, reading.length * 3 + 24)
    if (length > maximumLength) return false
    return none { character ->
        character == '\uFFFD' ||
            character in '\uE000'..'\uF8FF' ||
            (character.isISOControl() && character != '\n' && character != '\t')
    }
}

private class ZenzaiModelManager(private val context: Context) {
    fun prepare(size: String): File? {
        val expectedSize = if (size == "xsmall") 20_970_304L else 73_871_936L
        val folder = "zenz-v3.2-$size-gguf"
        val destination = File(context.filesDir, "zenzai/$folder/ggml-model-Q5_K_M.gguf")
        if (destination.length() == expectedSize) return destination
        return runCatching {
            check(destination.parentFile?.mkdirs() != false) {
                "Could not create the Zenzai model directory"
            }
            val asset = "$folder/ggml-model-Q5_K_M.gguf"
            context.assets.open(asset).use { input ->
                FileOutputStream(destination).use { output -> input.copyTo(output, 1024 * 1024) }
            }
            destination.takeIf { it.length() == expectedSize }
                ?: error("Copied Zenzai model has an unexpected size: ${destination.length()}")
        }.onFailure { error ->
            Log.e("KeynakoZenzai", "Could not copy the $size model", error)
        }.getOrNull()
    }
}
