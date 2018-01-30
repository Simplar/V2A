varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;

void main()
{
    lowp vec4 color = texture2D(inputImageTexture, textureCoordinate);
    gl_FragColor = vec4(color.rgb, 1.);
}
