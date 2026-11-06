import{n as e,t}from"./ScrollTrigger.BZVPcu9T.js";var n={desktop:{location:[2.802799940109253,.44999998807907104,1.600000023841858],rotation:[[.8929950594902039,-.06671450287103653,.44509434700012207],[.4500664472579956,.13237112760543823,-.8831297159194946],[-8.548180829848206e-8,.9889525175094604,.14823272824287415]],lens_mm:20,sensor_mm:36,sensor_height_mm:24,sensor_fit:`HORIZONTAL`,resolution:[2560,1440],room:{width:6.7056000000000004,depth:6.7056000000000004,height:2.7432000000000003,curb:.06}},phone:{location:[2.802799940109253,.44999998807907104,1.600000023841858],rotation:[[.8929950594902039,-.06671450287103653,.44509434700012207],[.4500664472579956,.13237112760543823,-.8831297159194946],[-8.548180829848206e-8,.9889525175094604,.14823272824287415]],lens_mm:20,sensor_mm:36,sensor_height_mm:24,sensor_fit:`VERTICAL`,resolution:[1296,1620],room:{width:6.7056000000000004,depth:6.7056000000000004,height:2.7432000000000003,curb:.06}}},r=[`s1`,`s1e`,`s2`,`s3`,`s4`,`s5e`,`s5`],i={fade:0,grind:1,roll:2,flake:3},a=[{kind:`hold`,a:0,w:.8,cap:0},{kind:`fade`,a:0,b:1,w:.55,cap:1},{kind:`hold`,a:1,w:.25,cap:1},{kind:`grind`,a:1,b:2,w:1.7,cap:2},{kind:`hold`,a:2,w:.45,cap:2},{kind:`roll`,a:2,b:3,w:1.3,cap:3},{kind:`hold`,a:3,w:.4,cap:3},{kind:`flake`,a:3,b:4,w:1.7,cap:4},{kind:`hold`,a:4,w:.4,cap:4},{kind:`roll`,a:4,b:5,w:1.3,cap:5},{kind:`fade`,a:5,b:6,w:.6,cap:6},{kind:`hold`,a:6,w:.9,cap:6}],o=a.reduce((e,t)=>e+t.w,0);function s(e){let t=.5-.5*Math.cos(Math.PI*e);return e*.7+t*.3}function c(e){let t=0,n=Math.min(Math.max(e,0),1)*o;for(let e of a){if(n<=t+e.w||e===a[a.length-1]){let r=Math.min(Math.max((n-t)/e.w,0),1);return e.kind===`hold`?{a:e.a,b:e.a,mode:0,t:0,cap:e.cap}:{a:e.a,b:e.b,mode:i[e.kind],t:e.kind===`fade`?r:s(r),cap:e.cap}}t+=e.w}return{a:6,b:6,mode:0,t:0,cap:6}}function l(e){let t=Array.from({length:e},()=>[1/0,-1/0]),n=0;for(let e of a){let r=t[e.cap];r[0]=Math.min(r[0],n/o),r[1]=Math.max(r[1],(n+e.w)/o),n+=e.w}return t}Math.round(o*1.15);var u=`#version 300 es
in vec2 a_pos;
out vec2 v_uv;
void main() {
  v_uv = a_pos * 0.5 + 0.5;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`,d=`#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 o;

uniform sampler2D u_a;
uniform sampler2D u_b;
uniform sampler2D u_key;
uniform int u_mode;
uniform float u_t;

uniform vec2 u_coverScale;
uniform vec2 u_coverOffset;
uniform vec2 u_imgSize;

uniform vec3 u_cam;
uniform mat3 u_rot;
uniform vec2 u_tan;
uniform vec2 u_yRange;   // metres: first and last floor line in view
uniform float u_width;   // room width, metres

uniform float u_grain;

float hash11(float p) {
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
             mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int k = 0; k < 4; k++) {
    s += a * vnoise(p);
    p = p * 2.03 + 17.1;
    a *= 0.5;
  }
  return s;
}

vec3 toLinear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 toSrgb(vec3 c) { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

void main() {
  vec2 iuv = v_uv * u_coverScale + u_coverOffset;
  vec2 tuv = vec2(iuv.x, 1.0 - iuv.y);           // images are stored top-down
  vec3 a = toLinear(texture(u_a, tuv).rgb);
  vec3 b = toLinear(texture(u_b, tuv).rgb);
  float key = texture(u_key, tuv).r;
  bool surface = key > 0.01;

  // Floor position under this pixel.
  vec2 ndc = iuv * 2.0 - 1.0;
  vec3 dir = u_rot * vec3(ndc.x * u_tan.x, ndc.y * u_tan.y, -1.0);
  float hit = dir.z < -1e-4 ? -u_cam.z / dir.z : 1e4;
  vec3 P = u_cam + dir * hit;
  float x = P.x;
  float y = P.y;

  float t = clamp(u_t, 0.0, 1.0);
  float glob = t * t * (3.0 - 2.0 * t);
  float m = glob;
  float span = u_yRange.y - u_yRange.x;

  if (surface && u_mode == 1) {
    // Grinder passes: lanes across the slab, each head a rounded front,
    // lanes staggered like a crew working side to side.
    float lane = 0.66;
    float li = floor((x + u_width * 0.5) / lane);
    float lc = (li + 0.5) * lane - u_width * 0.5;
    float stagger = hash11(li * 7.13 + 3.0) * 0.9;
    float q = (x - lc) / (lane * 0.5);
    float arc = 0.06 * sqrt(max(0.0, 1.0 - q * q));
    float front = mix(u_yRange.x - 0.2, u_yRange.y + 1.4, t) - stagger + arc
                + (fbm(vec2(x, y) * 4.0) - 0.5) * 0.12
                + (fbm(vec2(x, y) * 22.0) - 0.5) * 0.025;
    float d = front - y;
    m = smoothstep(-0.02, 0.02, d);
    // A faint, patchy haze of fresh dust right behind the heads.
    float speck = smoothstep(0.35, 0.75, fbm(vec2(x, y) * 40.0));
    float dust = m * exp(-max(d, 0.0) / 0.12) * speck;
    b = mix(b, b * 1.08 + 0.015, dust * 0.6);
  } else if (surface && u_mode == 2) {
    // Wet edge: roller-width scallops plus a little wander.
    float front = mix(u_yRange.x - 0.15, u_yRange.y + 0.35, t)
                + 0.016 * sin(x * 13.66 + 1.7) + 0.011 * sin(x * 4.9 + 0.4)
                + (fbm(vec2(x * 2.5, y * 2.5)) - 0.5) * 0.08
                + (fbm(vec2(x * 11.0, y * 11.0)) - 0.5) * 0.015;
    float d = front - y;
    m = smoothstep(-0.008, 0.008, d);
    // The freshest few centimetres are still wet and catch the light.
    b *= 1.0 + 0.22 * m * exp(-max(d, 0.0) / 0.05);
  } else if (surface && u_mode == 3) {
    // Broadcast: density ramps up over ~1.4 m behind an advancing front,
    // in uneven handfuls; each chip appears when density passes its key.
    float ramp = 1.4;
    float front = mix(u_yRange.x - 0.3, u_yRange.y + ramp + 0.5, t);
    float dens = (front - y) / ramp + (fbm(vec2(x, y) * 1.6) - 0.5) * 0.45;
    m = step(key, clamp(dens, 0.0, 1.2));
  }

  vec3 c = toSrgb(mix(a, b, m));

  // Static grain on the screen's own pixels: crisp at 1:1, never swimming.
  vec2 px = floor(gl_FragCoord.xy);
  float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float g = (hash12(px) - 0.5) * u_grain;
  vec3 gc = vec3(hash12(px + 11.3), hash12(px + 27.1), hash12(px + 41.7)) - 0.5;
  c += (g + gc * u_grain * 0.3) * (1.0 - 0.6 * lum);

  o = vec4(c, 1.0);
}`,f=[`u_a`,`u_b`,`u_key`,`u_mode`,`u_t`,`u_coverScale`,`u_coverOffset`,`u_imgSize`,`u_cam`,`u_rot`,`u_tan`,`u_yRange`,`u_width`,`u_grain`];function p(e,t,n){let r=e.createShader(t);if(e.shaderSource(r,n),e.compileShader(r),!e.getShaderParameter(r,e.COMPILE_STATUS))throw Error(e.getShaderInfoLog(r)??`shader compile failed`);return r}function m(e){return new Promise((t,n)=>{let r=new Image;r.decoding=`async`,r.crossOrigin=`anonymous`,r.onload=()=>r.decode().then(()=>t(r),()=>t(r)),r.onerror=()=>n(Error(`could not load ${e}`)),r.src=e})}var h=class{canvas;cam;gl;u;textures=[];key=null;imgSize;last=``;constructor(e,t,n){this.canvas=e,this.cam=t;let r=e.getContext(`webgl2`,{antialias:!1,alpha:!1,premultipliedAlpha:!1,preserveDrawingBuffer:!1,powerPreference:`high-performance`});if(!r)throw Error(`no webgl2`);this.gl=r;let i=r.createProgram();if(r.attachShader(i,p(r,r.VERTEX_SHADER,u)),r.attachShader(i,p(r,r.FRAGMENT_SHADER,d)),r.bindAttribLocation(i,0,`a_pos`),r.linkProgram(i),!r.getProgramParameter(i,r.LINK_STATUS))throw Error(r.getProgramInfoLog(i)??`link failed`);r.useProgram(i),this.u=Object.fromEntries(f.map(e=>[e,r.getUniformLocation(i,e)]));let a=r.createBuffer();r.bindBuffer(r.ARRAY_BUFFER,a),r.bufferData(r.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),r.STATIC_DRAW),r.enableVertexAttribArray(0),r.vertexAttribPointer(0,2,r.FLOAT,!1,0,0),this.textures=Array(n).fill(null),this.imgSize=[t.resolution[0],t.resolution[1]],this.setCamera()}setCamera(){let{gl:e,cam:t}=this,[n,r]=t.resolution,i,a;t.sensor_fit===`VERTICAL`?(a=(t.sensor_height_mm??24)/2/t.lens_mm,i=a*n/r):(i=t.sensor_mm/2/t.lens_mm,a=i*r/n);let o=t.rotation,s=new Float32Array([o[0][0],o[1][0],o[2][0],o[0][1],o[1][1],o[2][1],o[0][2],o[1][2],o[2][2]]);e.uniform3fv(this.u.u_cam,t.location),e.uniformMatrix3fv(this.u.u_rot,!1,s),e.uniform2f(this.u.u_tan,i,a),e.uniform1f(this.u.u_width,t.room.width),e.uniform2f(this.u.u_yRange,this.nearestFloorY(i,a),t.room.depth),e.uniform1i(this.u.u_a,0),e.uniform1i(this.u.u_b,1),e.uniform1i(this.u.u_key,2),e.uniform1f(this.u.u_grain,.03)}nearestFloorY(e,t){let{location:n,rotation:r}=this.cam,i=1/0;for(let a=0;a<=16;a++){let o=[(a/16*2-1)*e,-t,-1],s=[0,1,2].map(e=>r[e][0]*o[0]+r[e][1]*o[1]+r[e][2]*o[2]);s[2]<0&&(i=Math.min(i,n[1]+s[1]*(-n[2]/s[2])))}return Number.isFinite(i)?i:.5}upload(e,t){let{gl:n}=this,r=n.createTexture();n.bindTexture(n.TEXTURE_2D,r),n.pixelStorei(n.UNPACK_FLIP_Y_WEBGL,!1),n.pixelStorei(n.UNPACK_PREMULTIPLY_ALPHA_WEBGL,!1),n.pixelStorei(n.UNPACK_COLORSPACE_CONVERSION_WEBGL,t?n.NONE:n.BROWSER_DEFAULT_WEBGL),n.pixelStorei(n.UNPACK_ALIGNMENT,1),t?n.texImage2D(n.TEXTURE_2D,0,n.R8,n.RED,n.UNSIGNED_BYTE,e):n.texImage2D(n.TEXTURE_2D,0,n.RGBA8,n.RGBA,n.UNSIGNED_BYTE,e);let i=t?n.NEAREST:n.LINEAR;return n.texParameteri(n.TEXTURE_2D,n.TEXTURE_MIN_FILTER,i),n.texParameteri(n.TEXTURE_2D,n.TEXTURE_MAG_FILTER,i),n.texParameteri(n.TEXTURE_2D,n.TEXTURE_WRAP_S,n.CLAMP_TO_EDGE),n.texParameteri(n.TEXTURE_2D,n.TEXTURE_WRAP_T,n.CLAMP_TO_EDGE),r}setStill(e,t){this.textures[e]=this.upload(t,!1),this.imgSize=[t.naturalWidth,t.naturalHeight],this.last=``}setKey(e){this.key=this.upload(e,!0),this.last=``}has(e){return!!this.textures[e]}ready(...e){return!!this.key&&e.every(e=>this.textures[e])}resize(){let e=Math.min(window.devicePixelRatio||1,2),t=Math.round(this.canvas.clientWidth*e),n=Math.round(this.canvas.clientHeight*e);(this.canvas.width!==t||this.canvas.height!==n)&&(this.canvas.width=t,this.canvas.height=n,this.last=``);let r=t/n,i=this.cam.resolution[0]/this.cam.resolution[1],{gl:a}=this;if(r>i){let e=i/r;a.uniform2f(this.u.u_coverScale,1,e),a.uniform2f(this.u.u_coverOffset,0,(1-e)/2)}else{let e=r/i;a.uniform2f(this.u.u_coverScale,e,1),a.uniform2f(this.u.u_coverOffset,(1-e)/2,0)}a.viewport(0,0,t,n)}draw(e){let t=`${e.a}|${e.b}|${e.mode}|${e.t.toFixed(5)}|${this.canvas.width}x${this.canvas.height}`;if(t===this.last)return;let n=this.textures[e.a],r=this.textures[e.b]??n;if(!n||!this.key)return;this.last=t;let{gl:i}=this;i.activeTexture(i.TEXTURE0),i.bindTexture(i.TEXTURE_2D,n),i.activeTexture(i.TEXTURE1),i.bindTexture(i.TEXTURE_2D,r),i.activeTexture(i.TEXTURE2),i.bindTexture(i.TEXTURE_2D,this.key),i.uniform1i(this.u.u_mode,e.mode),i.uniform1f(this.u.u_t,e.t),i.uniform2f(this.u.u_imgSize,this.imgSize[0],this.imgSize[1]),i.drawArrays(i.TRIANGLES,0,3)}};e.registerPlugin(t);var g=`/ked-coatings/`.replace(/\/$/,``);function _(e){let t=e.clientHeight>e.clientWidth*1.05,n=t?`phone`:`desktop`,r=e.clientWidth*Math.min(window.devicePixelRatio||1,2);return{layout:n,width:t?r>900?1296:864:r>1700?2560:1600}}function v(e,[t,n],r,i,a){let o=i?1:Math.min(Math.max((e-t)/r,0),1),s=a?1:Math.min(Math.max((n-e)/r,0),1),c=Math.min(o,s);return c*c*(3-2*c)}function y(t){let i=t.querySelector(`[data-process-stage]`),a=t.querySelector(`canvas`),o=t.querySelector(`[data-process-track]`),s=[...t.querySelectorAll(`[data-caption]`)],u=[...t.querySelectorAll(`[data-tick]`)],d=t.querySelector(`[data-progress]`),{layout:f,width:p}=_(i),y=n[f],b;try{b=new h(a,y,r.length)}catch{t.classList.remove(`is-live`);return}let x=l(s.length),S={p:0},C=!1,w=()=>{b.resize();let e=c(S.p),t=b.has(e.a)?e.a:b.has(e.b)?e.b:-1;if(t<0||!b.ready(t))return;let n=b.has(e.b)?e.b:t;b.draw({a:t,b:n,mode:n===t&&e.a!==e.b?0:e.mode,t:n===t?0:e.t}),C||(C=!0,a.classList.add(`is-ready`))},T=()=>{let e=S.p;s.forEach((t,n)=>{let r=v(e,x[n],.022,n===0,n===s.length-1);t.style.opacity=r.toFixed(3),t.style.transform=`translate3d(0, ${((1-r)*14).toFixed(2)}px, 0)`,t.style.visibility=r<.01?`hidden`:`visible`});let t=c(e).cap;u.forEach(e=>e.classList.toggle(`is-on`,Number(e.dataset.tick)<=t)),d&&(d.style.transform=`scaleX(${e.toFixed(4)})`)};e.to(S,{p:1,ease:`none`,scrollTrigger:{trigger:o,start:`top top`,end:`bottom bottom`,scrub:.5},onUpdate:()=>{w(),T()}}),new ResizeObserver(()=>w()).observe(i),a.addEventListener(`webglcontextlost`,e=>{e.preventDefault(),t.classList.remove(`is-live`)});let E=e=>`${g}/process/${f}/${e}-${p}.${e===`key`?`png`:`webp`}`;(async()=>{let[e,t]=await Promise.all([m(E(`key`)),m(E(r[0]))]);b.setKey(e),b.setStill(0,t),w();for(let e=1;e<r.length;e++)b.setStill(e,await m(E(r[e]))),w()})().catch(()=>t.classList.remove(`is-live`)),T()}var b=document.querySelector(`[data-process]`);b?.classList.contains(`is-live`)&&y(b);