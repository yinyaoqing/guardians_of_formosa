shader_type canvas_item;

// 「紙上的戲」全螢幕後處理：描邊 + 紙紋 + 紙色偏。
//
// 掛法：CanvasLayer > ColorRect（全螢幕）> material = 這支 shader。
// 精緻度規格 L3 的延伸——風格由 shader 在執行期統一套用，資產只提供形狀與色塊，
// 風格漂移在結構上不可能發生；改章節氛圍只改參數，不重畫。
//
// 描邊：對螢幕亮度做 Sobel，邊緣壓成焦茶墨線。皮影是深色剪影貼在亮紙上，
//       亮度差本來就大，邊緣抓得很穩；地圖上細碎的東西也會被統一收成線稿。
// 紙紋：兩層程序噪聲——細顆粒（每像素 hash）+ 橫向纖維（拉長的 value noise）。
//       都用 FRAGCOORD 取樣，所以顆粒大小不隨相機縮放改變，像真的紙不像貼圖。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform bool enabled = true;

group_uniforms ink;
uniform vec4 ink_color : source_color = vec4(0.227, 0.165, 0.133, 1.0); // 焦茶 #3A2A22
uniform float ink_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ink_threshold : hint_range(0.0, 1.0) = 0.16;
uniform float ink_width : hint_range(0.5, 3.0) = 1.0;

group_uniforms paper;
uniform vec4 paper_color : source_color = vec4(0.910, 0.863, 0.776, 1.0); // 蚵殼灰 #E8DCC6
uniform float paper_tint : hint_range(0.0, 1.0) = 0.22;
uniform float grain_amount : hint_range(0.0, 0.5) = 0.09;
uniform float fiber_amount : hint_range(0.0, 0.5) = 0.10;
uniform float fiber_scale : hint_range(0.5, 8.0) = 2.5;
uniform float vignette : hint_range(0.0, 1.0) = 0.30;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;

	if (enabled) {
		// --- 描邊：Sobel on luminance ---
		vec2 px = SCREEN_PIXEL_SIZE * ink_width;
		float tl = luma(texture(screen_tex, uv + vec2(-px.x, -px.y)).rgb);
		float t  = luma(texture(screen_tex, uv + vec2( 0.0,  -px.y)).rgb);
		float tr = luma(texture(screen_tex, uv + vec2( px.x, -px.y)).rgb);
		float l  = luma(texture(screen_tex, uv + vec2(-px.x,  0.0)).rgb);
		float r  = luma(texture(screen_tex, uv + vec2( px.x,  0.0)).rgb);
		float bl = luma(texture(screen_tex, uv + vec2(-px.x,  px.y)).rgb);
		float b  = luma(texture(screen_tex, uv + vec2( 0.0,   px.y)).rgb);
		float br = luma(texture(screen_tex, uv + vec2( px.x,  px.y)).rgb);
		float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
		float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
		float edge = sqrt(gx * gx + gy * gy);
		float ink = smoothstep(ink_threshold, ink_threshold + 0.18, edge) * ink_strength;
		col = mix(col, ink_color.rgb, clamp(ink, 0.0, 1.0));

		// --- 紙色偏：往紙的色相拉，亮部拉得多、墨線幾乎不動 ---
		float lum = luma(col);
		vec3 papered = paper_color.rgb * (0.35 + 0.75 * lum);
		col = mix(col, papered, paper_tint * smoothstep(0.15, 0.6, lum));

		// --- 紙紋：以螢幕像素座標取樣，不隨相機縮放 ---
		vec2 pc = FRAGCOORD.xy;
		float grain = hash12(pc) - 0.5;
		// 纖維：x 方向拉長 → 橫向纖維；再疊一層 y 方向較短的，像手抄紙的交錯
		float fx = vnoise(vec2(pc.x * 0.012, pc.y * 0.22) * fiber_scale) - 0.5;
		float fy = vnoise(vec2(pc.x * 0.20, pc.y * 0.018) * fiber_scale + 17.0) - 0.5;
		float fiber = fx * 0.7 + fy * 0.3;
		col *= 1.0 + grain * grain_amount + fiber * fiber_amount;

		// --- 暈邊：舊紙邊緣略暗 ---
		float d = distance(uv, vec2(0.5));
		col *= 1.0 - vignette * smoothstep(0.38, 0.85, d);
	}

	COLOR = vec4(col, 1.0);
}
