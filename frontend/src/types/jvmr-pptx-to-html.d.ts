declare module '@jvmr/pptx-to-html' {
  export function pptxToHtml(buffer: ArrayBuffer): Promise<string[]>
}
