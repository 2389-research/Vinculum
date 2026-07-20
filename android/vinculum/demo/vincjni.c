#include <jni.h>
#include <string.h>
#include <stdint.h>
extern uint8_t* vinculum_render_displaylist(const char*, int32_t, int32_t, double, int32_t*);
extern void     vinculum_free(uint8_t*);
extern int32_t  vinculum_abi_version(void);
extern void     vinculum_set_font_dir(const char*);

JNIEXPORT jbyteArray JNICALL
Java_ai_vinc_VinculumNative_renderBytes(JNIEnv* e, jobject o, jstring latex, jboolean disp, jdouble size) {
    const char* s = (*e)->GetStringUTFChars(e, latex, 0);
    int32_t len = 0;
    uint8_t* buf = vinculum_render_displaylist(s, (int32_t)strlen(s), disp ? 1 : 0, size, &len);
    (*e)->ReleaseStringUTFChars(e, latex, s);
    if (!buf) return NULL;
    jbyteArray arr = (*e)->NewByteArray(e, len);
    (*e)->SetByteArrayRegion(e, arr, 0, len, (const jbyte*)buf);
    vinculum_free(buf);
    return arr;
}
JNIEXPORT void JNICALL
Java_ai_vinc_VinculumNative_setFontDir(JNIEnv* e, jobject o, jstring d) {
    const char* s = (*e)->GetStringUTFChars(e, d, 0);
    vinculum_set_font_dir(s);
    (*e)->ReleaseStringUTFChars(e, d, s);
}
JNIEXPORT jint JNICALL
Java_ai_vinc_VinculumNative_abiVersion(JNIEnv* e, jobject o) { return vinculum_abi_version(); }
