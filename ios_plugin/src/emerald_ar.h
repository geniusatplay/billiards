// Emerald Online 8 Ball Pool AR (was Emerald Break) - walk-around AR on iPhone / iPad (Apple ARKit), as a GDExtension.
//
// The Engine singleton "EmeraldAR" has exactly the methods of the Android plugin of the same name
// (android_plugin/.../EmeraldARPlugin.java), so src/ar/arcore_bridge.gd drives both the same way:
// getState() returns the same 40 numbers, getImageY()/getImageUV() the camera picture as a Y plane and
// an interleaved CbCr plane (NV12, full range), placeAnchor() takes x, y, z, qx, qy, qz, qw.
//
// This header has no Objective-C in it; everything ARKit lives in emerald_ar.mm.

#ifndef EMERALD_AR_H
#define EMERALD_AR_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class EmeraldAR : public Object {
	GDCLASS(EmeraldAR, Object);

	void *host = nullptr; // EARHost (Objective-C), retained

protected:
	static void _bind_methods();

public:
	EmeraldAR();
	~EmeraldAR();

	String availability();
	bool requestInstall();
	bool openAppSettings();
	bool share(const String &p_text, const String &p_title);
	String getLastError();
	String getInfo();
	bool start(int p_w, int p_h);
	void stop();
	void setViewSize(int p_w, int p_h);
	PackedFloat32Array getState();
	PackedByteArray getImageY();
	PackedByteArray getImageUV();
	bool placeAnchor(const PackedFloat32Array &p_pose);
	void clearAnchor();
};

} // namespace godot

#endif // EMERALD_AR_H
