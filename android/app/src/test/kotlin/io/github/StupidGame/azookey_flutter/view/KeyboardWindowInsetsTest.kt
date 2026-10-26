package io.github.StupidGame.azookey_flutter.view

import android.graphics.Insets
import android.os.Build
import android.view.WindowInsets
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 36], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class KeyboardWindowInsetsTest {
    @Test fun hiddenNavigationHintStillReservesTheHomeGestureArea() {
        assertEquals(KeyboardContentInsets(0, 0, 32), keyboardContentInsets(windowInsets(
            navigation = Insets.NONE, gestures = Insets.of(24, 0, 24, 32), mandatoryBottom = 20,
        )))
    }

    @Test fun overlappingBarsAndGesturesAreNotAddedTogether() {
        assertEquals(KeyboardContentInsets(0, 0, 48), keyboardContentInsets(windowInsets(
            navigation = Insets.of(0, 0, 0, 48), gestures = Insets.of(0, 0, 0, 32), mandatoryBottom = 20,
        )))
        assertEquals(KeyboardContentInsets(0, 0, 40), keyboardContentInsets(windowInsets(
            navigation = Insets.NONE, gestures = Insets.NONE, mandatoryBottom = 40,
        )))
    }

    @Test fun threeButtonNavigationNeedsNoGestureInsets() {
        assertEquals(KeyboardContentInsets(0, 0, 48), keyboardContentInsets(windowInsets(
            navigation = Insets.of(0, 0, 0, 48),
        )))
    }

    @Test fun sideNavigationIsReservedWithoutBlockingSideBackGestures() {
        assertEquals(KeyboardContentInsets(48, 12, 0), keyboardContentInsets(windowInsets(
            navigation = Insets.of(48, 0, 12, 0), gestures = Insets.of(100, 0, 100, 0),
        )))
    }

    @Test fun tappableElementsAreReservedAndImeInsetsAreIgnored() {
        assertEquals(KeyboardContentInsets(0, 0, 24), keyboardContentInsets(windowInsets(
            tappable = Insets.of(0, 0, 0, 24),
        )))
        assertEquals(KeyboardContentInsets(0, 0, 0), keyboardContentInsets(windowInsets()))
    }

    @Suppress("DEPRECATION")
    private fun windowInsets(
        navigation: Insets = Insets.NONE,
        gestures: Insets = Insets.NONE,
        mandatoryBottom: Int = 0,
        tappable: Insets = Insets.NONE,
    ): WindowInsets = WindowInsets.Builder().apply {
        if (Build.VERSION.SDK_INT >= 30) {
            setInsets(WindowInsets.Type.navigationBars(), navigation)
            setInsets(WindowInsets.Type.systemGestures(), gestures)
            setInsets(WindowInsets.Type.mandatorySystemGestures(), Insets.of(0, 0, 0, mandatoryBottom))
            setInsets(WindowInsets.Type.tappableElement(), tappable)
            setInsets(WindowInsets.Type.ime(), Insets.of(0, 0, 0, 500))
        } else {
            setSystemWindowInsets(navigation)
            setSystemGestureInsets(gestures)
            setMandatorySystemGestureInsets(Insets.of(0, 0, 0, mandatoryBottom))
            setTappableElementInsets(tappable)
        }
    }.build()
}
