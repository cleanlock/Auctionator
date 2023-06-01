AuctionatorSellingPostingHistoryRowMixin = CreateFromMixins(AuctionatorResultsRowTemplateMixin)

function AuctionatorSellingPostingHistoryRowMixin:OnClick(button, ...)
  Auctionator.Debug.Message("AuctionatorPostingHistoryRowMixin:OnClick()")

  Auctionator.EventBus
    :RegisterSource(self, "SellingPostingHistoryRow")
    :Fire(self, Auctionator.Selling.Events.PriceSelected, {buyout = self.rowData.price})
    :UnregisterSource(self)
end
