import { DialogUtil, LogUtil, ToastUtil } from "@pura/harmony-utils";
import { DialogAction } from "@pura/harmony-utils/src/main/ets/entity/constraint";
import { SourceAdapter } from "../adapter";
import { Avatar } from "../component/Avatar";
import { SettingGroup } from "../component/SettingGroup";
import { TitleHeader } from "../component/TitleHeader";
import { BreakpointConstants } from "../constants/BreakpointConstants";
import { StyleConstants } from "../constants/StyleConstants";
import { SettingItem } from "../model/SettingItem";
import { SourceConfig } from "../type/Adapter";
import { PreferencesCache } from "../util/PreferenceCache";
import { SlideDownControl } from "../util/SlideDownController";
import { AboutSetting, PlayerSetting, SoftwareSetting } from "../viewmodel/SettingGroupData";
import { About } from "./About";
import {Personalized_settings}from '../view/Personalized_settings'
@Component
export struct Setting {
  @State translateY: number = 16;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @Consume('NavPathStack') pageStack: NavPathStack;
  @State isExpanded: boolean = false
  @StorageLink("setting_page_sheet_show") isShow: boolean = false
  @State currentStep: number = 0
  @State formData: SourceConfig = {
    id: `user_data_source_${Date.now()}`,
    name: '',
    url: '',
    description: '',
    auth: {
      token: '',
      signAt: Date.now()
    }
  }
  @StorageLink("user_data_source") adapters: SourceConfig[] = PreferencesCache.getUserDataSource()
  @State currentIndex: number = -1
  @State isEditing: boolean = false // 新增：标记是否处于编辑模式
  private scrollController: Scroller = new ListScroller()
  // QR Code 相关状态
  @State qrCodeUrl: string = ''
  @State qrCodeUnikey: string = ''
  @State qrCodeStatus: number = 0 // -1 过期，0 等待扫码，1 等待确认，2 授权登录成功
  @State isCheckingQRCode: boolean = false
  @State qrCodeStatusText: string = '请扫描二维码'
  @State tokenFromQR: string = ''
  @State qrCodeVisible: boolean = false
  @State qrCodeScale: number = 0.8
  private qrCodeCheckTimer: number = 0
  // 设置存储
  @StorageLink("PlayerSetting") playerSetting: SettingItem[] = PlayerSetting
  @StorageLink("SoftwareSetting") softwareSetting: SettingItem[] = SoftwareSetting
  @StorageLink("about_page_show") aboutPageShow: boolean = false
  @StorageLink("setting_page_sheet_content") nowSheet: string = "form"

  calculateCurrentIndex(offset: number): number {
    offset = Math.abs(offset)
    return offset < 40 ? -1 : 0
  }

  onMenuIconClick(index: number) {
    if (index === 0) {
      this.pageStack.pop()
    }
  }

  private validateUrl(url: string): boolean {
    const urlPattern = /^(http|https):\/\/[a-zA-Z0-9-.]+(:\d+)?(\/[a-zA-Z0-9-._?&=]*)?$/
    return urlPattern.test(url)
  }

  // 优化：数据源的连接方法
  private connectToDataSource() {
    const cookie = this.formData.auth?.token
    if (!cookie) {
      ToastUtil.showShort('请填写令牌凭证')
      return
    }

    SourceAdapter.getConnectionStatus(this.formData)
      .then((source) => {
        if (this.isEditing) {
          // 编辑现有数据源
          PreferencesCache.updateUserDataSource(source)
          ToastUtil.showShort('数据源已更新')
        } else {
          // 添加新数据源
          PreferencesCache.addUserDataSource(source)
          ToastUtil.showShort('数据源已添加')
        }

        Promise.all([
          SourceAdapter.getRecommendList(),
          SourceAdapter.getRecommendSongs(),
          SourceAdapter.getRecommendArtists(),
          SourceAdapter.getTopList()
        ])
        this.isShow = false
        this.clearQRCodeTimer()
      })
      .catch((error: Error) => {
        ToastUtil.showShort(`连接失败: ${error.message}`)
      })
  }

  // 新增：编辑数据源方法
  private editSource(source: SourceConfig) {
    this.isEditing = true
    this.formData = JSON.parse(JSON.stringify(source)) // 深拷贝，避免直接修改原对象
    this.currentStep = 0
    this.isShow = true
    this.nowSheet = "form"

    // 清空二维码相关状态
    this.clearQRCodeTimer()
    this.qrCodeUrl = ''
    this.qrCodeUnikey = ''
    this.qrCodeStatus = 0
    this.tokenFromQR = ''
    this.qrCodeStatusText = '请扫描二维码'
    this.qrCodeVisible = false
    this.qrCodeScale = 0.8
  }

  private async generateQRCode() {
    if (!this.validateUrl(this.formData.url)) {
      ToastUtil.showShort('请先输入有效的数据源地址')
      return
    }

    try {
      // 先重置状态
      this.qrCodeStatus = 0
      this.qrCodeStatusText = '正在生成二维码...'
      this.tokenFromQR = ''

      // 确保先将可见性设为false，这样才能触发新的动画
      this.qrCodeVisible = false
      this.qrCodeScale = 0.8

      // 获取二维码密钥
      this.qrCodeUnikey = await SourceAdapter.getQRCodeKey(this.formData)

      // 生成二维码
      const qrCode = await SourceAdapter.createQRCode(this.formData, this.qrCodeUnikey)
      this.qrCodeUrl = qrCode.qrimg
      this.qrCodeStatusText = '请扫描二维码'

      // 使用setTimeout确保DOM先更新，再开始动画
      setTimeout(() => {
        animateTo({
          duration: 350,
          curve: Curve.EaseOut,
        }, () => {
          this.qrCodeVisible = true
          this.qrCodeScale = 1.0
        })
      }, 50)

      this.startCheckingQRCode()
    } catch (error) {
      LogUtil.error('QRCode', `Failed to generate QR code: ${error.message}`)
      this.qrCodeStatusText = '二维码生成失败'
      ToastUtil.showShort(`二维码生成失败: ${error.message}`)
    }
  }

  private startCheckingQRCode() {
    this.isCheckingQRCode = true
    this.checkQRCodeStatus()

    // 每 3 秒检查一次二维码状态
    this.qrCodeCheckTimer = setInterval(() => {
      this.checkQRCodeStatus()
    }, 3000)
  }

  private async checkQRCodeStatus() {
    if (!this.isCheckingQRCode || !this.qrCodeUnikey) {
      return
    }

    try {
      const checkResult = await SourceAdapter.checkQRCodeStatus(this.formData, this.qrCodeUnikey)
      this.qrCodeStatus = checkResult.status

      switch (checkResult.status) {
        case -1:
          this.qrCodeStatusText = '二维码已过期，请重新生成'
          this.clearQRCodeTimer()
          break
        case 0:
          this.qrCodeStatusText = '等待扫码...'
          break
        case 1:
          this.qrCodeStatusText = '请在手机上确认登录'
          break
        case 2:
          this.qrCodeStatusText = '授权登录成功'
          this.tokenFromQR = checkResult.cookie

          if (this.tokenFromQR) {
            if (!this.formData.auth) {
              this.formData.auth = { token: '', signAt: Date.now() }
            }
            this.formData.auth.token = this.tokenFromQR
          }

          this.clearQRCodeTimer()
          break
      }
    } catch (error) {
      LogUtil.error('QRCode', `Failed to check QR code status: ${error.message}`)
    }
  }

  private clearQRCodeTimer() {
    this.isCheckingQRCode = false
    if (this.qrCodeCheckTimer) {
      clearInterval(this.qrCodeCheckTimer)
      this.qrCodeCheckTimer = 0
    }
  }

  aboutToDisappear() {
    this.clearQRCodeTimer()
  }

  @Builder
  Title() {
    TitleHeader({
      title: $r('app.string.settings'),
      backActive: this.currentIndex === 0,
    })
  }

  @Builder
  AddSourceButton() {
    Row() {
      Image($r('app.media.ic_plus'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.icon_normal'))
      Text(this.adapters?.length ? '添加数据源' : '添加第一个数据源')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 8 })
    }
    .padding(12)
    .width(StyleConstants.FULL_WIDTH)
    .borderRadius(8)
    // .backgroundColor($r('app.color.setting_item_background'))
    .backgroundBlurStyle(BlurStyle.Regular)
    .onClick(() => {
      // 完全重置所有表单状态
      this.isEditing = false // 确保是添加模式
      this.formData = {
        id: `user_data_source_${Date.now()}`,
        name: '',
        url: '',
        description: '',
        auth: {
          token: '',
          signAt: Date.now(),
        }
      }
      this.currentStep = 0
      this.isShow = true
      this.nowSheet = "form"

      // 清空二维码相关状态
      this.clearQRCodeTimer()
      this.qrCodeUrl = ''
      this.qrCodeUnikey = ''
      this.qrCodeStatus = 0
      this.tokenFromQR = ''
      this.qrCodeStatusText = '请扫描二维码'
      this.qrCodeVisible = false
      this.qrCodeScale = 0.8
    })
  }

  @Builder
  QRCodeSection() {
    Column() {
      Divider()
        .color($r('app.color.divider'))
        .opacity(0.5)
        .margin({ top: 8, bottom: 8 })

      Text('或使用二维码扫码登录')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width(StyleConstants.FULL_WIDTH)

      // 管理按钮和二维码的显示逻辑
      if (!this.qrCodeUrl || !this.qrCodeVisible) {
        // 显示按钮
        Button('获取二维码')
          .width(140)
          .height(40)
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.generateQRCode()
          })
          .margin({ top: 4 })
      } else if (this.qrCodeUrl) {
        // 显示二维码
        Column({ space: 4 }) {
          Image(this.qrCodeUrl)
            .width(180)
            .height(180)
            .objectFit(ImageFit.Contain)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .opacity(this.qrCodeVisible ? 1 : 0)
            .scale({ x: this.qrCodeScale, y: this.qrCodeScale })
            .animation({
              duration: 350,
              curve: Curve.EaseOut
            })

          Text(this.qrCodeStatusText)
            .fontSize(14)
            .fontColor(this.qrCodeStatus === 2 ? $r('app.color.success') :
              this.qrCodeStatus === -1 ? $r('app.color.error') :
              $r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .width(StyleConstants.FULL_WIDTH)
            .opacity(this.qrCodeVisible ? 1 : 0)
            .animation({
              delay: 150,
              duration: 250,
              curve: Curve.EaseOut
            })
        }
        .alignItems(HorizontalAlign.Center)
      }

      // 状态相关的按钮
      if (this.qrCodeStatus === 2 && this.tokenFromQR) {
        Row() {
          Text('已获取令牌')
            .fontSize(14)
            .fontColor($r('app.color.success'))

          Image($r('app.media.ic_checkmark'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.success'))
            .margin({ left: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .opacity(this.qrCodeVisible ? 1 : 0)
        .animation({
          delay: 100,
          duration: 300,
          curve: Curve.EaseOut
        })
      }

      if (this.qrCodeStatus === -1) {
        Button('重新获取二维码')
          .width(140)
          .height(40)
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.generateQRCode()
          })
          .opacity(this.qrCodeVisible ? 1 : 0)
          .animation({
            delay: 100,
            duration: 300,
            curve: Curve.EaseOut
          })
      }
    }
    .width(StyleConstants.FULL_WIDTH)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.currentStep === 1 ? 1 : 0)
    .translate({ x: this.currentStep === 1 ? 0 : '20%' })
    .animation({ delay: 200, duration: 250, curve: Curve.FastOutSlowIn })
    .margin({ bottom: 16 })
  }

  @Builder
  FormContent() {
    Stack() {
      // 第一页表单
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('数据源名称 *')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 50, duration: 250, curve: Curve.FastOutSlowIn })

          TextInput({ placeholder: '请输入数据源名称', text: $$this.formData.name })
            .width(StyleConstants.FULL_WIDTH)
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 100, duration: 250, curve: Curve.FastOutSlowIn })
        }

        Column({ space: 8 }) {
          Text('数据源地址 *')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 150, duration: 250, curve: Curve.FastOutSlowIn })

          TextInput({ placeholder: '请输入数据源地址', text: $$this.formData.url })
            .width(StyleConstants.FULL_WIDTH)
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 200, duration: 250, curve: Curve.FastOutSlowIn })
        }

        Column({ space: 8 }) {
          Text('数据源描述')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 250, duration: 250, curve: Curve.FastOutSlowIn })

          TextArea({ placeholder: '请输入数据源描述', text: $$this.formData.description })
            .width(StyleConstants.FULL_WIDTH)
            .height(100)
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 300, duration: 250, curve: Curve.FastOutSlowIn })
        }

        Row() {
          Blank()
          Button('下一步')
            .width(120)
            .height(40)
            .backgroundColor($r('app.color.button_background'))
            .fontColor($r('app.color.text_primary'))
            .enabled(this.formData.name.trim() !== '' && this.formData.url.trim() !== '' &&
            this.validateUrl(this.formData.url))
            .onClick(() => {
              animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
                this.currentStep = 1
              })
            })
            .opacity(this.currentStep === 0 ? 1 : 0)
            .translate({ x: this.currentStep === 0 ? 0 : '-20%' })
            .animation({ delay: 350, duration: 250, curve: Curve.FastOutSlowIn })
        }
      }
      .width(StyleConstants.FULL_WIDTH)
      .padding(16)
      .opacity(this.currentStep === 0 ? 1 : 0)
      .translate({ x: this.currentStep === 0 ? 0 : '-100%' })
      .animation({ duration: 300, curve: Curve.FastOutSlowIn })

      // 第二页表单
      Column() {
        Row() {
          Row() {
            Image($r('app.media.ic_back'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.text_primary'))
            Text($r('app.string.back'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 2 })
          }
          .height(28)
          .borderRadius(14)
          .padding({ left: 6, right: 10 })
          .backgroundColor($r('app.color.back_button_normal'))
          .onClick(() => {
            // 只处理页面切换，不重置二维码状态
            animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
              this.currentStep = 0
              this.clearQRCodeTimer()
            })
          })
          .opacity(this.currentStep === 1 ? 1 : 0)
          .translate({ x: this.currentStep === 1 ? 0 : '20%' })
          .animation({ delay: 50, duration: 250, curve: Curve.FastOutSlowIn })
        }
        .width(StyleConstants.FULL_WIDTH)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)

        Column({ space: 8 }) {
          Text('令牌凭证')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(this.currentStep === 1 ? 1 : 0)
            .translate({ x: this.currentStep === 1 ? 0 : '20%' })
            .animation({ delay: 100, duration: 250, curve: Curve.FastOutSlowIn })

          TextInput({ placeholder: '请输入令牌凭证', text: this.tokenFromQR || (this.formData.auth?.token || '') })
            .width(StyleConstants.FULL_WIDTH)
            .type(InputType.Password)
            .onChange((value) => {
              if (!this.formData.auth) {
                this.formData.auth = { token: '', signAt: Date.now() }
              }
              this.formData.auth.token = value
            })
            .opacity(this.currentStep === 1 ? 1 : 0)
            .translate({ x: this.currentStep === 1 ? 0 : '20%' })
            .animation({ delay: 150, duration: 250, curve: Curve.FastOutSlowIn })
        }
        .margin({ top: 16 })

        this.QRCodeSection()

        Blank()

        Row({ space: 8 }) {
          Button(this.isEditing ? '保存修改' : '确认添加')
            .width(120)
            .height(40)
            .backgroundColor($r('app.color.button_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.connectToDataSource()
            })
            .opacity(this.currentStep === 1 ? 1 : 0)
            .translate({ y: this.currentStep === 1 ? 0 : '20%' })
            .animation({ delay: 250, duration: 250, curve: Curve.FastOutSlowIn })
        }
        .margin({ bottom: 16 })
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .padding(16)
      .opacity(this.currentStep === 1 ? 1 : 0)
      .translate({ x: this.currentStep === 1 ? 0 : '100%' })
      .animation({ duration: 300, curve: Curve.FastOutSlowIn })
    }
    .width(StyleConstants.FULL_WIDTH)
    .height(StyleConstants.FULL_HEIGHT)
  }
  @Builder
  Personalized_Settings(){
    Personalized_settings()
  }
  // 修改：AdapterItem 添加长按菜单
  @Builder
  AdapterItemMenu(adapter: SourceConfig) {
    Menu() {
      MenuItem({ content: '编辑', labelInfo: '' })
        .onClick(() => {
          this.editSource(adapter)
        })
      MenuItem({ content: '删除', labelInfo: '' })
        .onClick(() => {
          DialogUtil.showPrimaryDialog({
            title: '删除数据源',
            message: `是否删除数据源"${adapter.name}"？`,
            primaryButton: "取消",
            secondaryButton: "删除",
            onAction: (action) => {
              if (action == DialogAction.TWO) {
                PreferencesCache.deleteUserDataSource(adapter.id)
                ToastUtil.showShort('数据源已删除')
              }
            }
          })
        })
    }
  }

  @Builder
  AdapterItem(adapter: SourceConfig) {
    Row() {
      Avatar({ url: adapter.auth?.user?.avatar })
        .width(40)
        .height(40)

      Column({ space: 4 }) {
        Text(adapter.auth?.user?.name ?? adapter.name)
          .fontSize(16)
          .fontColor($r('app.color.text_title'))
          .fontWeight(FontWeight.Medium)

        if (adapter.auth?.user) {
          Text(adapter.name)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Blank()

      // 新增：菜单按钮
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Image($r('app.media.ic_more'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.icon_normal'))
      }
      .width(32)
      .height(32)
      .backgroundColor('transparent')
      .bindMenu(this.AdapterItemMenu(adapter))

      Image($r('app.media.ic_arrow_down_3'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.icon_normal'))
        .rotate({ z: 1, angle: this.isExpanded ? 180 : 0 })
        .animation({
          duration: 250,
          curve: Curve.FastOutSlowIn
        })
        .margin({ left: 8 })
    }
    .onClick(() => {
      animateTo({
        duration: 250,
        curve: Curve.FastOutSlowIn
      }, () => {
        this.isExpanded = !this.isExpanded
      })
    })
    .padding(16)
    .width(StyleConstants.FULL_WIDTH)
    .borderRadius(8)
    // .backgroundColor($r('app.color.setting_item_background'))
    .backgroundBlurStyle(BlurStyle.Regular)
  }

  @Builder
  AboutPage() {
    About()
  }
  @Builder
  sheet() {
    if (this.nowSheet === "about") {
      this.AboutPage()
    }else if (this.nowSheet === "form"){
      this.FormContent()
    }else if (this.nowSheet === "Personalized_settings"){
      this.Personalized_Settings()
    }
  }
  build() {
    NavDestination() {
      this.Title()

      Column() {

        List({ scroller: this.scrollController }) {
          ListItem() {
            Row() {
              Text(SlideDownControl.getReturnActionText(this.currentIndex))
                .fontColor($r('app.color.text_secondary'))
                .fontWeight(StyleConstants.FONT_WEIGHT_FIVE)
                // .margin({ left: 8 })
                .opacity(this.currentIndex >= 0 ? 1 : 0)
                .translate({ y: this.currentIndex >= 0 ? 0 : -20 })
                .animation({
                  duration: 250,
                  curve: Curve.FastOutSlowIn
                })
            }
            .height(this.currentIndex >= 0 ? 40 : 0)
            .animation({
              duration: 250,
              curve: Curve.FastOutSlowIn
            })
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width(StyleConstants.FULL_WIDTH)
            .padding({
              left: 16,
              right: 16
            })
          }

          ListItemGroup({ header: this.SourceButton() }) {
            ListItem() {
              SettingGroup({
                title: $r('app.string.setting_player'),
                items: this.playerSetting
              })
            }

            ListItem() {
              SettingGroup({
                title: $r('app.string.setting_cache'),
                items: this.softwareSetting
              })
            }

            ListItem() {
              SettingGroup({
                title: $r('app.string.setting_about'),
                items: AboutSetting
              })
            }
            ListItem().height(80).backgroundColor('transparent')
          }
          .translate({ y: this.translateY })
          .animation({
            duration: 250,
            curve: Curve.LinearOutSlowIn
          })
          .onAppear(() => { this.translateY = 0 })
        }
        .borderRadius(8)
        .backToTop(true)
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width(StyleConstants.FULL_WIDTH)
        .height(StyleConstants.FULL_HEIGHT)
        .sticky(StickyStyle.Header | StickyStyle.Footer)
        .onWillScroll((_scrollOffset: number, scrollState: ScrollState) => {
          if (scrollState === ScrollState.Scroll) {
            const positionY = this.scrollController.currentOffset().yOffset
            if (positionY < 0) {
              this.currentIndex = SlideDownControl.calculateCurrentIndex(positionY, 0)
            } else {
              this.currentIndex = -1
            }
          }
        })
        .onScrollStop(() => {
          this.onMenuIconClick(this.currentIndex)
          this.currentIndex = -1
        })
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .padding({ left: 12, right: 12 })
    }
    .hideToolBar(true)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
    .mode(NavDestinationMode.STANDARD)
    .expandSafeArea()
    .width(StyleConstants.FULL_WIDTH)
    .height(StyleConstants.FULL_HEIGHT)
    .bindSheet($$this.isShow, this.sheet, {
      showClose: this.nowSheet !== "form",
      height:SheetSize.FIT_CONTENT,
      detents: [SheetSize.MEDIUM],
      preferType: this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? SheetType.BOTTOM : SheetType.CENTER
    })
    .gesture(
      SwipeGesture({
        direction: SwipeDirection.Vertical,
      }).onAction((event) => {
        if (event.angle >= 0) {
          this.pageStack.pop()
        }
      })
    )
  }

  @Builder
  SourceButton() {
    Column(){
      if (!this.adapters?.length) {
        this.AddSourceButton()
      } else {
        Column({ space: 8 }) {
          this.AdapterItem(this.adapters[0])

          if (this.adapters.length > 0) {
            Column({ space: 8 }) {
              ForEach(this.adapters.slice(1), (adapter: SourceConfig) => {
                this.AdapterItem(adapter)
              })
              this.AddSourceButton()
            }
            .height(this.isExpanded ? undefined : 0)
            .opacity(this.isExpanded ? 1 : 0)
            .animation({
              duration: 250,
              curve: Curve.FastOutSlowIn
            })
          }
        }
      }
    }
    .padding(12)
  }
}