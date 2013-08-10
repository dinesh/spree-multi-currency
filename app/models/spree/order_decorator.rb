# encoding: utf-8

Spree::OrderContents.class_eval do

    def add_to_line_item(line_item, variant, quantity, currency=nil, shipment=nil)
      if line_item
        line_item.target_shipment = shipment
        line_item.quantity += quantity.to_i
        line_item.currency = currency unless currency.nil?
        line_item.save
      else
        line_item = Spree::LineItem.new(quantity: quantity)
        line_item.target_shipment = shipment
        line_item.variant = variant
        if currency
          line_item.currency = currency unless currency.nil?
          line_item.price    = variant.price_in(currency).amount
        else
          line_item.price    = variant.price
        end
        order.line_items << line_item
        line_item
      end

      order.reload
      line_item
    end

end

Spree::Order.class_eval do
  extend Spree::MultiCurrency
  multi_currency :item_total, :total,
                 rate_at_date: lambda { |t| t.created_at },
                 only_read: true

  def update_totals
    # update_adjustments
    self.payment_total = payments.completed.map(&:amount).sum
    self.item_total = line_items.map(&:amount).sum
    self.adjustment_total = adjustments.map(&:amount).sum
    self.total = read_attribute(:item_total) + adjustment_total
  end

  # this will return only the highest shipping cost
  # if the calculator fixed price (per item) was used.
  # not tested with any other calculators
  def rate_hash
    highest_cost=0
    available_shipping_methods(:front_end).map do |ship_method|
      next unless cost = ship_method.calculator.compute(self)
      if cost > highest_cost
        highest_cost = cost
        @ship_method = ship_method
      end
    end
    @rate_hash ||= [{ id: @ship_method.id,
                      shipping_method: @ship_method,
                      name: @ship_method.name,
                      cost: highest_cost }]
  end

  def update!
    update_totals
    updater.update_payment_state

    # give each of the shipments a chance to update themselves
    shipments.each { |shipment| shipment.update!(self) }
    updater.update_shipment_state
    updater.update_adjustments
    # update totals a second time in case updated adjustments
    # have an effect on the total
    update_totals
    update_attributes_without_callbacks({
      payment_state: payment_state,
      shipment_state: shipment_state,
      item_total: read_attribute(:item_total),
      adjustment_total: adjustment_total,
      payment_total: payment_total,
      total: read_attribute(:total)
    })

    # ensure checkout payment always matches order total
    # FIXME implement for partitial payments
    if payment? && payments.first.checkout? && payments.first.amount != total
      payments.first.update_attributes_without_callbacks(amount: total)
    end

    update_hooks.each { |hook| self.send hook }
  end
=begin
  def add_variant(variant, quantity = 1)
      current_item = contains?(variant)
      if current_item
        current_item.quantity += quantity
        current_item.save
      else
        current_item = Spree::LineItem.new(quantity: quantity)
        current_item.variant = variant
        # FIXME dry this string
        actual_price = variant.prices.where(currency: Spree::Config.currency).where('currency not null and amount not null').limit(1)
        if actual_price
            current_item.price = actual_price.amount
            current_item.currency = Spree::Config.currency
        else
            actual_price = variant.prices.where('currency not null and amount not null').limit(1)
            current_item.price = actual_price.amount
            current_item.currency = actual_price.currency
        end
        self.line_items << current_item
      end

      # populate line_items attributes for additional_fields entries
      # that have populate => [:line_item]
      Spree::Variant.additional_fields.select { |f| !f[:populate].nil? && f[:populate].include?(:line_item) }.each do |field|
        value = ''

        name = field[:name].gsub(' ', '_').downcase
        if field[:only].nil? || field[:only].include?(:variant)
          value = variant.send(name)
        elsif field[:only].include?(:product)
          value = variant.product.send(name)
        end
        current_item.update_attribute(name, value)
      end

      self.reload
      current_item
  end
=end

end
