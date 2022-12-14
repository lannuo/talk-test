<template>
  <div class="vlt-wrapper">
    <div v-if="showDialog" class="vlt-dialog">
      <div>{{ local.permission }}</div>
      <button>{{ local.cancel }}</button>
    </div>
    <div>
      <svg
        t="1641739095332"
        class="icon"
        viewBox="0 0 1024 1024"
        version="1.1"
        xmlns="http://www.w3.org/2000/svg"
        p-id="30001"
        width="100"
        height="120"
      >
        <path
          d="M746.666667 405.333333a21.333333 21.333333 0 0 0-21.333334 21.333334v106.666666a213.333333 213.333333 0 0 1-426.666666 0v-106.666666a21.333333 21.333333 0 0 0-42.666667 0v106.666666a256 256 0 0 0 234.666667 256v106.666667h-128a21.333333 21.333333 0 0 0 0 42.666667h298.666666a21.333333 21.333333 0 1 0 0-42.666667h-128v-106.666667a256 256 0 0 0 234.666667-256v-106.666666a21.333333 21.333333 0 0 0-21.333333-21.333334z"
          p-id="30002"
          fill="#e6e6e6"
        ></path>
        <path
          d="M512 704a170.666667 170.666667 0 0 0 170.666667-170.666667V256a170.666667 170.666667 0 0 0-341.333334 0v277.333333a170.666667 170.666667 0 0 0 170.666667 170.666667z m-128-448a128 128 0 0 1 256 0v277.333333a128 128 0 0 1-256 0z"
          p-id="30003"
          fill="#e6e6e6"
        ></path>
      </svg>
    </div>
    <div class="vlt-wave" ref="wave"></div>
    <div class="vlt-volume">
      <input type="range" min="0.0" max="1.0" step="0.01" v-model="volume" />
    </div>
    <div class="vlt-runlog">{{ runlog }}</div>
    <div class="vlt-player"></div>
  </div>
</template>
<script>
// 必须引入的核心，换成require也是一样的。注意：recorder-core会自动往window下挂载名称为Recorder对象，全局可调用window.Recorder，也许可自行调整相关源码清除全局污染
import Recorder from './recorder/recorder-core'

// 可选的扩展支持项
import './recorder/extensions/frequency.histogram.view'
import './recorder/extensions/lib.fft'
// 实时流播放器
import './recorder/extensions/buffer_stream.player'

import { mergeOptions } from './recorder/utils'

const MEDIA_TYPE = 'pcm'

const DEFAULTS = {
  url: 'ws://localhost:9090/ws/talk',
  imei: '10007012346',
  chn: 0
}

export default {
  name: 'VueLiveTalk',
  props: {
    local: {
      type: Object,
      default() {
        return {
          busy: '设备繁忙',
          cancel: '忽略',
          connecting: '连接中',
          connected: '已连接(等待设备语音)',
          disconnected: '已断开',
          error: '错误',
          errCodec: '不支持的编码',
          errCross: '无权录音(跨域)',
          errHttps: '无权录音(需https)',
          errSocket: '连接错误',
          errSupport: '此浏览器不支持录音',
          init: '未启动',
          noAllow: '用户拒绝录音权限',
          noMic: '无可用麦克风',
          offline: '终端掉线',
          talking: '通话中',
          timeout: '终端超时',
          kickout: '会话冲突'
        }
      }
    },
    /**
     * 采样率
     * mp3 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000
     * wav 任意
     */
    sampleRate: {
      type: Number,
      default: 16000
    }
  },
  data() {
    return {
      bitRate: 16,
      options: DEFAULTS,
      otherError: '',
      player: null,
      sendTime: 0,
      sendChunk: null,
      showDialog: false,
      socket: null,
      status: 0,
      recorder: null,
      // 音量 取值 0 - 2.0
      volume: 0.5,
      wave: null
    }
  },
  computed: {
    runlog() {
      let ret = ''
      switch (this.status) {
        case 0:
          ret = this.local.init
          break
        case 1:
          ret = this.local.connecting
          break
        case 2:
          ret = this.local.connected
          break
        case 3:
          ret = this.local.disconnected
          break
        case 4:
          ret = this.local.errSocket
          break
        case 5:
          ret = this.local.noAllow
          break
        case 6:
          ret = this.local.talking
          break
        case 7:
          ret = this.local.errCross
          break
        case 8:
          ret = this.local.errHttps
          break
        case 9:
          ret = this.local.noMic
          break
        case 99:
          ret = this.local.error
          break
        case 3000:
          ret = this.local.error
          break
        case 3001:
          ret = this.local.timeout
          break
        case 3002:
          ret = this.local.busy
          break
        case 3003:
          ret = this.local.errCodec
          break
        case 3004:
          ret = this.local.kickout
          break
        case 3005:
          ret = this.local.offline
          break
      }
      return ret
    }
  },
  methods: {
    /**
     * 关闭对讲
     */
    close(no) {
      if (this.player) {
        this.player.stop()
        this.player = null
      }
      if (this.socket) {
        this.socket.close()
        this.socket = null
      }
      this.recordStop()
      this.recordClose()
      if (no === false || no === undefined) {
        this.status = 0
      }
    },
    /**
     * 创建录音对象
     */
    createRecord() {
      this.recorder = Recorder({
        type: MEDIA_TYPE,
        sampleRate: this.sampleRate,
        bitRate: this.bitRate,
        audioTrackSet: { echoCancellation: true, noiseSuppression: true },
        onProcess: (
          buffers,
          powerLevel,
          bufferDuration,
          bufferSampleRate,
          newBufferIdx,
          asyncEnd
        ) => {
          // 输入音频数据，更新显示波形
          this.drawWave(
            buffers[buffers.length - 1],
            powerLevel,
            bufferSampleRate
          )
          // 实时数据处理，清理内存
          this.realTimeOnProcess(
            buffers,
            powerLevel,
            bufferDuration,
            bufferSampleRate,
            newBufferIdx,
            asyncEnd
          )
        }
      })
    },
    /**
     * 创建实时流播放器
     */
    createPlayer(playSampleRate) {
      if (this.player) {
        this.player.stop()
        this.player = null
      }
      // this.player = new (window.AudioContext || window.webkitAudioContext)()
      // this.player._source = this.player.createBufferSource()

      this.player = Recorder.BufferStreamPlayer({
        // 传输过来的不是pcm就需要开启解码
        decode: false,
        onInputError: (errMsg, inputIndex) => {
          window.console.log(
            '第' + inputIndex + '次的音频片段input输入出错: ' + errMsg,
            1
          )
        },
        transform: (pcm, sampleRate, True, False) => {
          sampleRate = playSampleRate
          // pcm需指定sampleRate，为传输过来pcm的采样率
          True(new Int16Array(pcm), sampleRate)
          // True(pcm, sampleRate)
        }
      })
      // 切换成了实时模式，如果缓冲中积压的未播放数据量过大，会直接丢弃数据或者加速播放，达到尽快播放新输入的数据的目的，可有效降低播放延迟
      this.player.set.realtime = false
      // 打开
      this.player.start(
        () => {},
        (err) => {
          window.console.Log('播放器打开失败: ' + err)
        }
      )
    },
    /**
     * 创建websocket通讯
     */
    createWs() {
      if (typeof WebSocket === 'undefined') {
        window.console.log('您的浏览器不支持WebSocket')
      } else {
        this.status = 1
        // 实现化WebSocket对象
        // 指定要连接的服务器地址与端口建立连接
        // 注意ws、wss使用不同的端口。我使用自签名的证书测试，
        // 无法使用wss，浏览器打开WebSocket时报错
        // ws对应http、wss对应https。
        const sTmp = this.options.url.substr(
          this.options.url.length - 1,
          this.options.url.length
        )
        if (sTmp === '/') {
          this.options.url = this.options.url.substr(
            0,
            this.options.url.length - 1
          )
        }
        this.socket = new WebSocket(
          // this.options.url +
          //   '/' +
          //   this.options.imei +
          //   '/' +
          //   this.options.chn +
          //   '?type=2&duration=3000'
          this.options.url +
            '/' +
            this.options.imei +
            '/pcm/' +
            this.sampleRate +
            '/' +
            this.options.chn
        )
        // 连接打开事件
        this.socket.onopen = () => {
          this.status = 2
        }
        // 收到消息事件
        this.socket.onmessage = (msg) => {
          // 收到消息后 播放
          this.processMsg(msg.data)
        }
        // 连接关闭事件
        this.socket.onclose = (e) => {
          if (e.code > 2999) {
            this.status = e.code
          } else {
            this.status = 3
          }
        }
        // 发生了错误事件
        this.socket.onerror = (e) => {
          this.status = 4
        }
      }
    },
    drawWave(buffer, powerLevel, bufferSampleRate) {
      // 复制一次 防止调整音量后影响波形显示
      const newbuf = Int16Array.from(buffer)
      this.wave.input(newbuf, powerLevel, bufferSampleRate)
    },
    /**
     * 播放实时流
     */
    playBuffer(arrayBuffer, sampleRate) {
      this.status = 6
      // 创建播放器
      if (this.player == null) {
        this.createPlayer(sampleRate)
      }
      if (this.player) {
        this.player.input(arrayBuffer)
      }
    },
    processMsg(msg) {
      if (msg === null) {
        return
      }
      // blob 转 ArrayBuffer
      msg.arrayBuffer().then((buffer) => {
        this.playBuffer(buffer, this.sampleRate)
      })
    },
    /**
     * 实时处理时清理一下内存（延迟清理），本方法先于RealTimeSendTry执行
     */
    realTimeOnProcess(
      buffers,
      powerLevel,
      bufferDuration,
      bufferSampleRate,
      newBufferIdx
      // asyncEnd
    ) {
      this.sendChunk = null
      // 调整音量
      const newBuf = buffers
      this.scaleSamples(newBuf[0], 0, newBuf[0].length, this.volume)
      // console.log("bufferSampleRate", bufferSampleRate)
      // console.log("this.sampleRate", this.sampleRate)
      // 借用SampleData函数进行数据的连续处理，采样率转换是顺带的
      const chunk = Recorder.SampleData(
        buffers,
        bufferSampleRate,
        this.sampleRate,
        this.sendChunk,
        { frameType: MEDIA_TYPE }
      )

      // 清理已处理完的缓冲数据，释放内存以支持长时间录音，最后完成录音时不能调用stop，因为数据已经被清掉了
      this.recorder.buffers = []
      // 此时的chunk.data就是原始的音频pcm数据，直接保存即为pcm文件、加个wav头即为wav文件、丢给mp3编码器转一下码即为mp3文件
      // this.sendChunk = chunk

      // 没有新数据，或结束时的数据量太小，不能进行mock转码
      if (chunk.data.length === 0) {
        return
      }
      console.log("chunk.data.length", chunk.data.length);
      // console.log(chunk.data)
      const data = new Uint8Array(chunk.data.buffer)
      // console.log(data)
      this.transferUpload(data)
    },
    /**
     * 打开麦克风授权获得相关资源
     */
    recordOpen() {
      this.recorder.open(
        () => {
          // 打开麦克风授权获得相关资源

          // 如果开启了弹框，此处需要取消
          this.showDialog = false
          // 此处创建这些音频可视化图形绘制浏览器支持妥妥的
          this.wave = Recorder.FrequencyHistogramView({
            elem: this.$refs.wave,
            lineCount: 15,
            position: 0,
            minHeight: 1,
            fallDuration: 400,
            stripeEnable: false,
            mirrorEnable: true
          })
          // 创建websocket
          this.createWs()
          // 开始录音
          this.recordStart()
        },
        (msg, isUserNotAllow) => {
          // 用户拒绝未授权或不支持
          // 如果开启了弹框，此处需要取消
          this.showDialog = false
          if (isUserNotAllow) {
            this.status = 5
          } else {
            if (msg.indexOf('跨域') !== -1) {
              this.status = 7
            }
            if (msg.indexOf('https') !== -1) {
              this.status = 8
            }
            if (msg.indexOf('麦克风') !== -1) {
              this.status = 9
            }
            if (this.status === 7 || this.status === 8 || this.status === 9) {
              // no code
            } else {
              this.otherError = msg
              this.status = 99
            }
          }
        }
      )
    },
    /**
     * 关闭录音 释放资源
     */
    recordClose() {
      if (this.recorder) {
        this.recorder.close()
      }
    },
    /**
     * 开始录音
     */
    recordStart() {
      if (this.recorder && Recorder.IsOpen()) {
        this.recorder.start()
      }
    },
    /**
     * 停止录音
     */
    recordStop() {
      if (!(this.recorder && Recorder.IsOpen())) {
        return
      }
      this.recorder.stop()
    },
    /**
     * 音量调节
     */
    scaleSamples(samples, position, numSamples, volume) {
      const numChannels = 1
      const fixedPointVolume = Math.floor(volume * 4096.0)
      const start = position * numChannels
      const stop = start + numSamples * numChannels

      for (let xSample = start; xSample < stop; xSample++) {
        let value = (samples[xSample] * fixedPointVolume) >> 12
        if (value > 32767) {
          value = 32767
        } else if (value < -32767) {
          value = -32767
        }
        samples[xSample] = value
      }
    },
    talk(opts) {
      this.options = mergeOptions(this.options, opts)
      this.close()
      this.recordOpen()
    },
    /**
     * 上传
     */
    transferUpload(buffer) {
      // Socket.readyState，0 - 表示连接尚未建立，1 - 表示连接已建立，可以进行通信，2 - 表示连接正在进行关闭，3 - 表示连接已经关闭或者连接不能打开
      if (buffer && this.socket && this.socket.readyState === 1) {
        this.socket.send(buffer)
      }
    },
    sleep(numberMillis) {
      var now = new Date();
      var exitTime = now.getTime() + numberMillis;
      while(true){
        console.log("sleep....")
        now=new Date();
        if(now.getTime() > exitTime)
          return;
      }
    }
  },
  watch: {
    status(val) {
      if (val === 3 || val === 4 || val > 2999) {
        this.close(true)
      }
    }
  },
  created() {},
  mounted() {
    this.createRecord()
    // this.recordOpen()
  },
  beforeDestroy() {
    this.close()
  },
  destroyed() {
    // 销毁已持有的所有全局资源
    Recorder.Destroy()
  }
}
</script>
<style lang="scss">
.vlt-wrapper {
  position: relative;
  width: 160px;
  height: 200px;
  padding: 10px;
  box-sizing: border-box;
  border: 1px solid #ccc;
  font-size: 13px;

  .vlt-dialog {
    position: absolute;
    width: calc(100% - 20px);
  }

  .vlt-wave {
    height: 100px;
    width: calc(100% - 20px);
    position: absolute;
    top: 10px;
    left: 10px;
  }

  .vlt-runlog {
    color: #f00;
    position: absolute;
    left: 0;
    bottom: 5px;
    width: 100%;
    height: 30px;
    line-height: 30px;
  }

  .vlt-volume {
    width: 100%;
    input {
      width: 100%;
    }
  }
}
</style>
