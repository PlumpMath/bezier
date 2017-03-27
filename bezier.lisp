;;;; bezier.lisp

(in-package #:bezier)

;;; "bezier" goes here. Hacks and glory await!

(defparameter *geom-lines* nil)
(defparameter *geom-lines-stream* nil)
(defparameter *tess-lines* nil)
(defparameter *tess-lines-stream* nil)
(defparameter *running* nil)
(defparameter *verts* 05.0)
(defparameter *time* (get-internal-real-time))

(defstruct-g g-poc
  (position :vec3 :accessor pos)
  (control :vec3 :accessor control)
  (color :vec4 :accessor col))

(defun-g vert ((point g-poc))
  (values (v! (pos point) 1.0)
          (v! (control point) 1.0)
          (col point)))

(defun-g vert ((point g-pc))
  (values (v! (pos point) 1.0)))

(def-glsl-stage tess-cont (&uniform ("verts" :float) &context :400 :tesselation-control)
  "
layout(vertices=4) out;

void main()
{
  gl_TessLevelOuter[0] = 1.0;
  gl_TessLevelOuter[1] = verts;
}
"
  ())

(def-glsl-stage tess-eval (&context :400 :tesselation-evaluation)
  "
layout(isolines) in;

void main()
{
  float t = gl_TessCoord.x;
  color_out = vec4(0.0, 0.5, 0.0, 1.0);
  float OneMinusT = 1.0 - t;
  float b0 = OneMinusT*OneMinusT*OneMinusT;
  float b1 = 3.0*t*OneMinusT*OneMinusT;
  float b2 = 3.0*t*t*OneMinusT;
  float b3 = t*t*t;
  gl_Position = b0*gl_in[0].gl_Position + b1*gl_in[1].gl_Position + b2*gl_in[2].gl_Position + b3*gl_in[3].gl_Position;
}"
  (("color_out" :vec4)))

(def-glsl-stage geom-glsl (("control" (:vec4 (*))) ("color" (:vec4 (*)))
                                                   &uniform
                                                   ("transform" :mat4)
                                                   ("detail" :int)
                                                   &context :330 :geometry)
  "
layout(lines) in;
layout(line_strip, max_vertices=20) out;

vec3 evaluateBezierPosition( vec3 v[4], float t )
{
    float OneMinusT = 1.0 - t;
    float b0 = OneMinusT*OneMinusT*OneMinusT;
    float b1 = 3.0*t*OneMinusT*OneMinusT;
    float b2 = 3.0*t*t*OneMinusT;
    float b3 = t*t*t;
    return b0*v[0] + b1*v[1] + b2*v[2] + b3*v[3];
}

/**
*	Main
*/
void main()
{
  color_out = color[0];
  vec3 pos[4];
  pos[0] = gl_in[0].gl_Position.xyz;
  pos[1] = control[0].xyz;
  pos[2] = control[1].xyz;
  pos[3] = gl_in[1].gl_Position.xyz;
  float OneOverDetail = 1.0 / float(detail-1.0);
  for( int i=0; i<detail; i++ )
  {
    float t = i * OneOverDetail;
    vec3 p = evaluateBezierPosition( pos, t );
    gl_Position = transform * vec4( p.xyz, 1.0 );
    EmitVertex();
  }

	EndPrimitive();
}" (("color_out" :vec4)))


(defun-g frag ((color :vec4))
  color)

(def-g-> main-prog (:line-strip)
  :vertex #'(vert g-poc)
  :geometry #'(geom-glsl (:vec4 (*)) (:vec4 (*)))
  :fragment #'(frag :vec4))

(def-g-> tess-prog (:patches)
  :vertex #'(vert g-pc)
  :tesselation-control #'(tess-cont)
  :tesselation-evaluation #'(tess-eval)
  :fragment #'(frag :vec4))

(defun step-demo ()
  (let* ((min-frame-time 1000/4)
         (delta-time (- (get-internal-real-time) *time*)))
    (when (< delta-time min-frame-time)
      (sleep (/ (- min-frame-time delta-time) 1000))
      (setf delta-time min-frame-time))
    (incf *time* delta-time))
  (clear)
  (map-g #'main-prog *geom-lines-stream* :transform (m4:scale (v! 1.0 1.0 1.0)) :detail 20)
  (map-g #'tess-prog *tess-lines-stream* :verts *verts*)
  (swap))

(defun run-loop ()
  (setf *running* t)
  (setf *geom-lines* (make-gpu-array
                 (list (list (v! -1.0 1.0 -0.1) (v! -1.0 0.0 0.0) (v! 0.0 0.0 1.0 1.0))
                       (list (v! 1.0 -1.0 -0.1) (v! 1.0 0.0 0.0) (v! 0.0 1.0 0.0 1.0)))
                 :element-type 'g-poc
                 :dimensions 2))
  (setf *geom-lines-stream* (make-buffer-stream *geom-lines* :retain-arrays t))
  (setf *tess-lines* (make-gpu-array
                      (list (list (v! -1.0 1.0 -0.1) (v! 0.0 0.0 1.0 1.0))
                            (list (v! -1.0 0.0 0.0) (v! 0.0 0.0 1.0 1.0))
                            (list (v! 1.0 0.0 0.0) (v! 0.0 1.0 0.0 1.0))
                            (list (v! 1.0 -1.0 -0.1) (v! 0.0 1.0 0.0 1.0)))
                      :element-type 'g-pc
                      :dimensions 4))
  (setf *tess-lines-stream* (make-buffer-stream *tess-lines* :retain-arrays t))
  (%gl:patch-parameter-i :patch-vertices 4)
  (gl:depth-func :lequal)
  (loop :while (and *running* (not (shutting-down-p))) :do
    (livesupport:continuable
      (step-demo)
      (livesupport:update-repl-link))))



