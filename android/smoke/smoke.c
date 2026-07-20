// JNI shim: bridges Java native methods to Vinculum's C ABI. Built with the
// Android clang against libVinculumAndroid.so (see README).
#include <jni.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

extern uint8_t* vinculum_render_displaylist(const char*, int32_t, int32_t, double, int32_t*);
extern void     vinculum_free(uint8_t*);
extern int32_t  vinculum_abi_version(void);
extern void     vinculum_set_font_dir(const char*);

JNIEXPORT void JNICALL
Java_com_vinc_MainActivity_setFontDir(JNIEnv* e, jobject t, jstring d) {
    const char* s = (*e)->GetStringUTFChars(e, d, 0);
    vinculum_set_font_dir(s);
    (*e)->ReleaseStringUTFChars(e, d, s);
}

JNIEXPORT jstring JNICALL
Java_com_vinc_MainActivity_render(JNIEnv* e, jobject t, jstring latex) {
    const char* s = (*e)->GetStringUTFChars(e, latex, 0);
    int32_t len = 0;
    uint8_t* buf = vinculum_render_displaylist(s, (int32_t)strlen(s), 1, 24.0, &len);
    char out[256];
    if (buf) {
        snprintf(out, sizeof out, "OK abi=%d bytes=%d magic=%c%c%c%c",
                 vinculum_abi_version(), len, buf[0], buf[1], buf[2], buf[3]);
        vinculum_free(buf);
    } else {
        snprintf(out, sizeof out, "NIL abi=%d", vinculum_abi_version());
    }
    (*e)->ReleaseStringUTFChars(e, latex, s);
    return (*e)->NewStringUTF(e, out);
}
