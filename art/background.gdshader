shader_type canvas_item;
uniform vec2 camera = vec2(0.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
 vec2 p=UV*vec2(10.0,6.25)+camera*0.00009;
 float n=noise(p*1.6+noise(p*3.2))*0.55+noise(p*6.4)*0.25+noise(p*12.8)*0.12;
 float cloud=pow(n,4.0);
 vec3 col=vec3(0.025,0.038,0.065)+vec3(0.055,0.13,0.25)*cloud;
 col+=vec3(0.05,0.035,0.08)*pow(noise(p+vec2(21.0)),5.0);
 COLOR=vec4(col,1.0);
}
