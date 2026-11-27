package example.chromesmoke;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import org.junit.Test;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.fail;

public class ChromeSmokeTest {
    private static final String CHROME = "com.android.chrome";
    private static final int MAX_SCROLLS = 20;

    @Test
    public void opensAdviserPageAndFindsConsultationLink() throws Exception {
        android.app.Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Bundle args = InstrumentationRegistry.getArguments();
        UiDevice device = UiDevice.getInstance(instrumentation);
        Uri startUrl = Uri.parse(args.getString("startUrl"));
        String startLabel = args.getString("startLabel");
        String destinationLabel = args.getString("destinationLabel");

        Intent openPage = new Intent(Intent.ACTION_VIEW, startUrl)
                .setPackage(CHROME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        instrumentation.getContext().startActivity(openPage);

        UiObject2 startLink = waitForStartLink(device, startLabel);
        assertNotNull("The consultation link was not found on the start page", startLink);
        assertNull("The destination text was already visible before the tap",
                findText(device, destinationLabel));
        startLink.click();

        // Let Chrome replace the initial page before searching further down.
        device.wait(Until.gone(By.text(startLabel)), 10_000);
        int x = device.getDisplayWidth() / 2;
        int height = device.getDisplayHeight();
        for (int scrolls = 0; scrolls <= MAX_SCROLLS; scrolls++) {
            UiObject2 visibleText = device.wait(Until.findObject(By.text(destinationLabel)), 1_200);
            if (visibleText != null || findText(device, destinationLabel) != null) {
                return;
            }
            if (scrolls < MAX_SCROLLS) {
                device.swipe(x, height * 76 / 100, x, height * 28 / 100, 18);
            }
        }
        fail("The destination consultation text was not visible after scrolling");
    }

    private UiObject2 waitForStartLink(UiDevice device, String label) {
        long deadline = android.os.SystemClock.elapsedRealtime() + 45_000;
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            UiObject2 link = findText(device, label);
            if (link != null) {
                return link;
            }

            // Fresh Play Store emulator images can show Chrome onboarding.
            for (String id : new String[]{"terms_accept", "negative_button", "no_thanks_button"}) {
                UiObject2 button = device.findObject(By.res(CHROME, id).clickable(true));
                if (button != null) {
                    button.click();
                    break;
                }
            }
            android.os.SystemClock.sleep(500);
        }
        return null;
    }

    private UiObject2 findText(UiDevice device, String label) {
        UiObject2 element = device.findObject(By.text(label));
        return element != null ? element : device.findObject(By.descContains(label));
    }
}
