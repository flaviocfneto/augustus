package com.github.Keriew.augustus;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.util.Log;
import android.widget.Toast;

import java.io.File;

import org.libsdl.app.SDLActivity;

public class AugustusMainActivity extends SDLActivity {
    private static final int GET_FOLDER_RESULT = 500;

    @Override
    public void onStop() {
        super.onStop();
        releaseAssetManager();
        FileManager.clearCache();
    }

    @Override
    protected String[] getLibraries() {
        String[] parentLibs = super.getLibraries();
        if (parentLibs.length > 0 && parentLibs[0].equals("SDL3")) {
             return new String[]{
                "SDL3",
                "SDL3_mixer",
                "augustus"
            };
        } else {
            return new String[]{
                "SDL2",
                "SDL2_mixer",
                "augustus"
            };
        }
    }

    @SuppressWarnings("unused")
    public void showDirectorySelection(boolean again) {
        if (getPackageManager().hasSystemFeature(PackageManager.FEATURE_LEANBACK) || !hasFolderPicker()) {
            useDefaultDirectory();
            return;
        }
        startActivityForResult(DirectorySelectionActivity.newIntent(this, again), GET_FOLDER_RESULT);
    }

    private boolean hasFolderPicker() {
        return new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).resolveActivity(getPackageManager()) != null;
    }

    // Android TV usually has no folder picker, so use the app's own external folder,
    // which needs no permissions: /sdcard/Android/data/<package>/files
    private void useDefaultDirectory() {
        File dir = getExternalFilesDir(null);
        if (dir == null) {
            FileManager.setBaseUri(Uri.EMPTY);
        } else {
            dir.mkdirs();
            FileManager.setBaseUri(Uri.fromFile(dir));
            String message = "Copy the Caesar 3 files to " + dir.getAbsolutePath();
            Log.i("augustus", message);
            runOnUiThread(() -> Toast.makeText(this, message, Toast.LENGTH_LONG).show());
        }
        gotDirectory();
    }

    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == GET_FOLDER_RESULT) {
            if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                FileManager.setBaseUri(data.getData());
            } else {
                FileManager.setBaseUri(Uri.EMPTY);
            }
            gotDirectory();
        } else {
            super.onActivityResult(requestCode, resultCode, data);
        }
    }

    @SuppressWarnings("unused")
    public float getScreenDensity() {
        return getResources().getDisplayMetrics().density;
    }

    private native void gotDirectory();
    private native void releaseAssetManager();
}
