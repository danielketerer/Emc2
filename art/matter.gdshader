shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.8, 0.6, 0.3, 1.0);
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float r = length(p);
 float z = sqrt(max(0.0, 1.0-r*r));
 vec2 q = p * 5.0 + vec2(seed, TIME * 0.035);
 float n = noise(q + noise(q * 1.8) * 2.5);
 float veins = pow(1.0-abs(n*2.0-1.0), 5.0);
 float light = 0.22 + 0.75*max(0.0,dot(normalize(vec3(p,z)),normalize(vec3(-0.6,-0.7,1.0))));
 vec3 body = tint.rgb * (light + n*0.7 + veins*0.32);
 float edge = pow(max(0.0,1.0-r),0.15);
 float halo = exp(-max(0.0,r-0.86)*9.0)*0.17;
 COLOR = vec4(body, smoothstep(1.01,0.97,r)*edge + halo*(1.0-smoothstep(1.0,1.4,r)));
}
